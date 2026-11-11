import Testing

@testable import BaseKit

@Suite struct FileNamesTests {
    @Test func renamesWithinTheSameFolderAndKeepsMarkdown() {
        #expect(FileNames.renaming("Notes/Plan.md", to: "Roadmap") == "Notes/Roadmap.md")
        #expect(FileNames.renaming("Plan.md", to: "Roadmap.md") == "Roadmap.md")
        #expect(FileNames.renaming("Plan.markdown", to: "Road map") == "Road map.markdown")
        #expect(FileNames.renaming("Plan.md", to: "  Roadmap  ") == "Roadmap.md")
        #expect(FileNames.renaming("Plan.md", to: "v1.2 notes") == "v1.2 notes.md")
        #expect(FileNames.renaming("Plan.md", to: "Ünïcödé 😀") == "Ünïcödé 😀.md")
    }

    @Test func refusesNamesThatArentOneVisibleFile() {
        #expect(FileNames.renaming("Plan.md", to: "") == nil)
        #expect(FileNames.renaming("Plan.md", to: "   ") == nil)
        #expect(FileNames.renaming("Plan.md", to: "a/b") == nil)
        #expect(FileNames.renaming("Plan.md", to: "a:b") == nil)
        #expect(FileNames.renaming("Plan.md", to: ".hidden") == nil)
        #expect(FileNames.renaming("Plan.md", to: ".md") == nil)
    }

    @Test func namesACopyThatDoesntExistYet() {
        let taken: Set = ["Notes/Plan copy.md", "Notes/Plan copy 2.md"]
        #expect(FileNames.copy(of: "Notes/Plan.md") { taken.contains($0) } == "Notes/Plan copy 3.md")
        #expect(FileNames.copy(of: "Plan.md") { _ in false } == "Plan copy.md")
        #expect(FileNames.copy(of: "README") { _ in false } == "README copy")
    }
}
