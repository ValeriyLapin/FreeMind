import AppKit

// 单实例：已有 FreeMind 在运行时把它调到前面，自己退出。必须在创建任何文档、启动 MCP 之前。
// 单元测试以本应用为宿主运行，要能和正在使用的 FreeMind 同时存在，所以不检查。
if !AppDelegate.isRunningTests, !SingleInstanceLock.acquire() {
    exit(0)
}

// 关闭或退出时询问是否保留修改。AppKit 在创建 NSDocumentController 前就读取这个键，所以必须在这里登记；
// 系统设置里明确关掉时以系统设置为准。
UserDefaults.standard.register(defaults: ["NSCloseAlwaysConfirmsChanges": true])

// 第一个创建的 NSDocumentController 会成为 shared，必须在 NSApp 启动前创建。
_ = DocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
