/// 同一页面的新刷新会使较早的异步结果失效；不同页面互不影响。
package struct PageRefreshIntent {
    package init() {}
    private var generations: [String: Int] = [:]

    package mutating func begin(_ page: String) -> Int {
        let next = (generations[page] ?? 0) &+ 1
        generations[page] = next
        return next
    }

    package func isCurrent(_ page: String, _ request: Int) -> Bool {
        generations[page] == request
    }
}
