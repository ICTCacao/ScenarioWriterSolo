import Foundation
import SQLite3

public struct SQLiteError: Error, LocalizedError {
    public let code: Int32
    public let message: String
    public var errorDescription: String? { "SQLite(\(code)): \(message)" }
}

/// SQLite3 C API の薄いラッパ（依存ライブラリなし）。
public final class SQLiteDatabase {
    private var db: OpaquePointer?
    public let path: String

    public init(path: String, readOnly: Bool = false, immutable: Bool = false) throws {
        self.path = path
        var flags: Int32 = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var target = path
        if immutable {
            // 書き込めない場所にある WAL モードの DB も -shm を作らずに読める
            flags |= SQLITE_OPEN_URI
            var comps = URLComponents()
            comps.scheme = "file"
            comps.path = path
            comps.queryItems = [URLQueryItem(name: "immutable", value: "1")]
            target = comps.string ?? path
        }
        let rc = sqlite3_open_v2(target, &db, flags, nil)
        guard rc == SQLITE_OK else {
            let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "open failed"
            sqlite3_close(db)
            throw SQLiteError(code: rc, message: msg)
        }
        sqlite3_busy_timeout(db, 3000)
    }

    deinit { sqlite3_close(db) }

    public var lastInsertRowId: Int64 { sqlite3_last_insert_rowid(db) }
    /// この接続で書き換えた行数の累計（未保存の変更があるかの判定に使う）
    public var totalChanges: Int64 { sqlite3_total_changes64(db) }
    public var changes: Int { Int(sqlite3_changes(db)) }

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err != nil ? String(cString: err!) : "exec failed"
            sqlite3_free(err)
            throw SQLiteError(code: rc, message: msg + " [" + sql.prefix(80) + "]")
        }
    }

    public func run(_ sql: String, _ params: [SQLiteValue?] = []) throws {
        let st = try Statement(db: db!, sql: sql)
        try st.bind(params)
        _ = try st.step()
    }

    public func query(_ sql: String, _ params: [SQLiteValue?] = []) throws -> [Row] {
        let st = try Statement(db: db!, sql: sql)
        try st.bind(params)
        var rows: [Row] = []
        while try st.step() { rows.append(st.row()) }
        return rows
    }

    public func scalarInt(_ sql: String, _ params: [SQLiteValue?] = []) throws -> Int64? {
        try query(sql, params).first?.int(0)
    }

    private var transactionDepth = 0

    /// 入れ子で呼んでも外側のトランザクションにまとめる
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        if transactionDepth > 0 {
            transactionDepth += 1
            defer { transactionDepth -= 1 }
            return try body()
        }
        try exec("BEGIN IMMEDIATE")
        transactionDepth = 1
        do {
            let r = try body()
            transactionDepth = 0
            try exec("COMMIT")
            return r
        } catch {
            transactionDepth = 0
            try? exec("ROLLBACK")
            throw error
        }
    }

    public func tableExists(_ name: String) throws -> Bool {
        (try scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?", [.text(name)]) ?? 0) > 0
    }

    public func columnExists(table: String, column: String) throws -> Bool {
        try query("PRAGMA table_info(\(table))").contains { $0.text("name") == column }
    }

    // MARK: -

    public enum SQLiteValue {
        case int(Int64), real(Double), text(String), blob(Data)
        public static func i(_ v: Int) -> SQLiteValue { .int(Int64(v)) }
    }

    public struct Row {
        fileprivate var values: [String: Any?]
        fileprivate var ordered: [Any?]
        public func int(_ name: String) -> Int64? { (values[name] ?? nil) as? Int64 }
        public func int(_ idx: Int) -> Int64? { ordered[idx] as? Int64 }
        public func double(_ name: String) -> Double? {
            if let d = (values[name] ?? nil) as? Double { return d }
            if let i = (values[name] ?? nil) as? Int64 { return Double(i) }
            if let s = (values[name] ?? nil) as? String { return Double(s) }
            return nil
        }
        public func text(_ name: String) -> String? {
            let v = values[name] ?? nil
            if let s = v as? String { return s }
            if let i = v as? Int64 { return String(i) }
            if let d = v as? Double { return String(d) }
            return nil
        }
        public func blob(_ name: String) -> Data? { (values[name] ?? nil) as? Data }
        public func intValue(_ name: String, _ def: Int = 0) -> Int {
            if let i = int(name) { return Int(i) }
            if let d = double(name) { return Int(d) }
            return def
        }
    }

    final class Statement {
        private var st: OpaquePointer?
        init(db: OpaquePointer, sql: String) throws {
            let rc = sqlite3_prepare_v2(db, sql, -1, &st, nil)
            guard rc == SQLITE_OK else { throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db)) + " [" + sql.prefix(120) + "]") }
        }
        deinit { sqlite3_finalize(st) }
        func bind(_ params: [SQLiteValue?]) throws {
            for (i, p) in params.enumerated() {
                let idx = Int32(i + 1)
                switch p {
                case .none: sqlite3_bind_null(st, idx)
                case .some(.int(let v)): sqlite3_bind_int64(st, idx, v)
                case .some(.real(let v)): sqlite3_bind_double(st, idx, v)
                case .some(.text(let v)): sqlite3_bind_text(st, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                case .some(.blob(let d)):
                    d.withUnsafeBytes { p in _ = sqlite3_bind_blob(st, idx, p.baseAddress, Int32(d.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                }
            }
        }
        func step() throws -> Bool {
            let rc = sqlite3_step(st)
            if rc == SQLITE_ROW { return true }
            if rc == SQLITE_DONE { return false }
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(sqlite3_db_handle(st))))
        }
        func row() -> Row {
            let n = sqlite3_column_count(st)
            var values: [String: Any?] = [:]
            var ordered: [Any?] = []
            for i in 0..<n {
                let name = String(cString: sqlite3_column_name(st, i))
                let v: Any?
                switch sqlite3_column_type(st, i) {
                case SQLITE_INTEGER: v = sqlite3_column_int64(st, i)
                case SQLITE_FLOAT: v = sqlite3_column_double(st, i)
                case SQLITE_TEXT: v = String(cString: sqlite3_column_text(st, i))
                case SQLITE_BLOB:
                    if let p = sqlite3_column_blob(st, i) { v = Data(bytes: p, count: Int(sqlite3_column_bytes(st, i))) } else { v = Data() }
                default: v = nil
                }
                values[name] = v
                ordered.append(v)
            }
            return Row(values: values, ordered: ordered)
        }
    }
}
