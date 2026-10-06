import CoreGraphics
import XCTest
@testable import PatternEngine
@testable import TimeModel

final class GridLayoutTests: XCTestCase {
    private let area = CGRect(x: 100, y: 80, width: 3000, height: 1700)

    private func makeLayout(
        total: Int, groupSizes: [Int] = [], majorGroupInterval: Int = 0,
        canvasWidth: Int = 3840, canvasHeight: Int = 2160, blocksPerRow: Int = 0
    ) -> GridPattern.Layout {
        var config = WallpaperConfig.default
        config.budget.contentScale = 1.0
        config.budget.maxMarkSizePoints = 1000 // do not let the ceiling drive these
        // These tests are about the layout rules, so they pin the block shape
        // rather than inheriting whatever the current defaults happen to be.
        config.budget.groupsPerBlock = 0 // follow the progress's major interval
        config.budget.blocksPerRow = blocksPerRow // 0: let the tiling be chosen
        let composition = Composition(
            config: config,
            canvas: CanvasSpec(
                pixelWidth: canvasWidth, pixelHeight: canvasHeight, scale: 2, appearance: .dark
            )
        )
        let progress = TimeModel.Progress(
            mode: groupSizes.isEmpty ? .year : .life,
            elapsed: total / 2, total: total, todayIndex: total / 2, dayKey: "2026-09-09",
            groupSizes: groupSizes, majorGroupInterval: majorGroupInterval
        )
        return GridPattern.Layout(progress: progress, composition: composition)
    }

    /// Every mark the layout claims to place, counted from its own metrics.
    private func placedCount(_ layout: GridPattern.Layout) -> Int {
        layout.remainder > 0
            ? layout.acrossCount * (layout.rowCount - 1) + layout.remainder
            : layout.acrossCount * layout.rowCount
    }

    // MARK: - Ungrouped

    func testAnExactDivisorIsPreferredOverTheAspectIdeal() {
        // 4160 marks with no grouping: 80 x 52 exactly, no stub row.
        let layout = makeLayout(total: 4160)
        XCTAssertEqual(layout.remainder, 0)
        XCTAssertEqual(placedCount(layout), 4160)
    }

    func testAYearFallsBackToTheAspectIdeal() {
        // 365 = 5 x 73 and nothing else, so a stub row is unavoidable.
        let layout = makeLayout(total: 365)
        XCTAssertGreaterThan(layout.remainder, 0)
        XCTAssertEqual(placedCount(layout), 365)
    }

    func testTheStubRowIsLeftAligned() {
        let layout = makeLayout(total: 365)
        let firstOfStub = layout.center(of: layout.acrossCount * (layout.rowCount - 1))
        let firstOfARowAbove = layout.center(of: 0)
        XCTAssertEqual(firstOfStub.x, firstOfARowAbove.x, accuracy: 0.0001,
                       "the tail of a run starts where every other row starts")
    }

    func testEveryMarkLandsOnTheLattice() {
        let layout = makeLayout(total: 365)
        for index in 0 ..< 365 {
            let center = layout.center(of: index)
            let column = (center.x - layout.origin.x - layout.radius) / layout.pitch.width
            let row = (center.y - layout.origin.y - layout.radius) / layout.pitch.height
            XCTAssertEqual(column, column.rounded(), accuracy: 0.0001, "index \(index)")
            XCTAssertEqual(row, row.rounded(), accuracy: 0.0001, "index \(index)")
        }
    }

    func testNoTwoMarksShareAPosition() {
        for total in [365, 366, 4160, 100, 7, 1] {
            let layout = makeLayout(total: total)
            var seen = Set<String>()
            for index in 0 ..< total {
                let center = layout.center(of: index)
                XCTAssertTrue(
                    seen.insert("\(Int(center.x.rounded()))x\(Int(center.y.rounded()))").inserted,
                    "total \(total), index \(index) collides"
                )
            }
        }
    }

    func testEveryMarkStaysOnTheCanvas() {
        for total in [1, 7, 365, 366, 4160] {
            let layout = makeLayout(total: total)
            for index in 0 ..< total {
                XCTAssertTrue(
                    CGRect(x: 0, y: 0, width: 3840, height: 2160).contains(layout.center(of: index))
                )
            }
        }
    }

    // MARK: - Grouped

    func testTimeRunsLeftToRightThenDownwards() {
        let layout = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        let first = layout.center(of: 0)
        let sameRow = layout.center(of: 51)
        let nextRow = layout.center(of: 52)

        XCTAssertGreaterThan(sameRow.x, first.x, "a year runs left to right")
        XCTAssertEqual(sameRow.y, first.y, accuracy: 0.0001, "a year stays on one row")
        XCTAssertGreaterThan(nextRow.y, first.y, "the next year is the next row down")
        XCTAssertEqual(nextRow.x, first.x, accuracy: 0.0001, "and starts back at the left")
    }

    func testALifeIsLaidOutAsYearsOfWeeks() {
        let layout = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        XCTAssertEqual(layout.acrossCount, 52, "52 weeks to a row")
        XCTAssertEqual(layout.rowCount, 80, "80 rows, one per year")
        XCTAssertEqual(placedCount(layout), 4160)
    }


    func testGroupingCostsSizeButNotFit() {
        let grouped = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        let plain = makeLayout(total: 4160)
        XCTAssertLessThan(grouped.radius, plain.radius, "gaps have to come out of somewhere")

        let canvas = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        for index in 0 ..< 4160 {
            XCTAssertTrue(canvas.contains(grouped.center(of: index)), "index \(index) escaped")
        }
    }

    func testYearsAreSeparatedInsideADecade() {
        let layout = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        let step = layout.center(of: 4 * 52).y - layout.center(of: 3 * 52).y
        XCTAssertGreaterThan(step, layout.radius * 2, "consecutive years must not touch")
    }

    // MARK: - Column blocks

    func testABlockIsADecade() {
        let layout = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        XCTAssertEqual(layout.rowsPerBlock, 10)
        XCTAssertEqual(layout.blockCount, 8)
        XCTAssertEqual(layout.rowsPerBlock * layout.blockCount, 80)
    }

    func testBlocksAreTiledAndWrapped() {
        let layout = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        XCTAssertGreaterThan(layout.blocksAcross, 1, "one column wastes a landscape canvas")
        XCTAssertGreaterThan(layout.blocksDown, 1, "and one row is not a rectangle either")

        // Second block: to the right of the first, on the same block-row.
        let first = layout.center(of: 0)
        let second = layout.center(of: layout.rowsPerBlock * 52)
        XCTAssertGreaterThan(second.x, first.x)
        XCTAssertEqual(second.y, first.y, accuracy: 0.0001)

        // The block that wraps: back to the left edge, one block-row down.
        let wrapped = layout.center(of: layout.blocksAcross * layout.rowsPerBlock * 52)
        XCTAssertEqual(wrapped.x, first.x, accuracy: 0.0001)
        XCTAssertGreaterThan(wrapped.y, first.y)
    }

    func testBlocksDoNotOverlap() {
        let layout = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        let lastWeekOfBlock = layout.center(of: layout.rowsPerBlock * 52 - 1)
        let firstWeekOfNext = layout.center(of: layout.rowsPerBlock * 52)
        XCTAssertGreaterThan(
            firstWeekOfNext.x - lastWeekOfBlock.x, layout.pitch.width,
            "there must be a gutter between blocks"
        )
    }

    func testTilingBuysBiggerMarksThanASingleColumn() {
        let tiled = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        let singleColumn = makeLayout(
            total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10, blocksPerRow: 1
        )
        XCTAssertGreaterThan(tiled.radius, singleColumn.radius)
    }

    func testMarksInsideAGroupStayContiguous() {
        let layout = makeLayout(total: 4160, groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10)
        for index in 1 ..< 52 {
            let a = layout.center(of: index - 1)
            let b = layout.center(of: index)
            let step = b.x - a.x
            XCTAssertEqual(step, layout.pitch.width, accuracy: 0.0001, "no gap inside a group")
        }
    }

    func testAPartialLastGroupIsStillPlaced() {
        // 4159 weeks: the last year is unfinished.
        var sizes = Array(repeating: 52, count: 80)
        sizes[79] = 51
        let layout = makeLayout(total: 4159, groupSizes: sizes, majorGroupInterval: 10)
        XCTAssertEqual(layout.rowCount, 80)
        let canvas = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        for index in 0 ..< 4159 {
            XCTAssertTrue(canvas.contains(layout.center(of: index)))
        }
    }
}

// MARK: - Months

extension GridLayoutTests {
    private var monthLengths: [Int] { [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] }

    private func monthLayout(leap: Bool = false) -> GridPattern.Layout {
        var sizes = monthLengths
        if leap { sizes[1] = 29 }
        return makeLayout(total: sizes.reduce(0, +), groupSizes: sizes)
    }

    func testAYearIsTwelveRowsOfDays() {
        let layout = monthLayout()
        XCTAssertEqual(layout.rowCount, 12, "one row per month")
        XCTAssertEqual(layout.acrossCount, 31, "as wide as the longest month")
    }

    func testEveryMonthStartsAtTheLeftEdge() {
        let layout = monthLayout()
        let left = layout.center(of: 0).x
        var start = 0
        for (month, length) in monthLengths.enumerated() {
            XCTAssertEqual(layout.center(of: start).x, left, accuracy: 0.0001, "month \(month + 1)")
            start += length
        }
    }

    func testAShortMonthEndsEarlyInsteadOfWrapping() {
        let layout = monthLayout()
        // 28 February: the last day of the short row sits three cells left of
        // where a 31-day month ends.
        let lastOfFebruary = layout.center(of: 31 + 27)
        let lastOfJanuary = layout.center(of: 30)
        XCTAssertEqual(lastOfFebruary.x, lastOfJanuary.x - 3 * layout.pitch.width, accuracy: 0.0001)
        XCTAssertGreaterThan(lastOfFebruary.y, lastOfJanuary.y, "and stays on its own row")
    }

    func testALeapFebruaryIsOneCellLonger() {
        let common = monthLayout()
        let leap = monthLayout(leap: true)
        XCTAssertEqual(
            Double(leap.center(of: 31 + 28).x - common.center(of: 31 + 27).x),
            Double(leap.pitch.width), accuracy: 0.5
        )
    }

    func testMonthsRunTopToBottom() {
        let layout = monthLayout()
        var previous = -CGFloat.greatestFiniteMagnitude
        var start = 0
        for length in monthLengths {
            let y = layout.center(of: start).y
            XCTAssertGreaterThan(y, previous)
            previous = y
            start += length
        }
    }

    func testEveryDayOfTheYearGetsItsOwnCell() {
        let layout = monthLayout(leap: true)
        var seen = Set<String>()
        for index in 0 ..< 366 {
            let center = layout.center(of: index)
            XCTAssertTrue(
                seen.insert("\(Int(center.x.rounded()))x\(Int(center.y.rounded()))").inserted,
                "day \(index) collides"
            )
        }
    }
}

// MARK: - Rows

extension GridLayoutTests {
    func testRowRangesCoverEveryMarkExactlyOnce() {
        for (total, sizes) in [(365, monthLengths), (4160, Array(repeating: 52, count: 80))] {
            let layout = makeLayout(
                total: total, groupSizes: sizes,
                majorGroupInterval: sizes.count == 80 ? 10 : 0
            )
            var covered: [Int] = []
            for row in 0 ..< layout.rowCount {
                covered.append(contentsOf: layout.rowRange(row))
            }
            XCTAssertEqual(covered, Array(0 ..< total), "total \(total)")
        }
    }

    func testUngroupedRowRangesStopAtTheStub() {
        let layout = makeLayout(total: 365)
        let last = layout.rowRange(layout.rowCount - 1)
        XCTAssertEqual(last.count, layout.remainder)
        XCTAssertEqual(last.upperBound, 365, "the stub must not run past the end")
    }
}

// MARK: - Block shape knobs

extension GridLayoutTests {
    private func blockLayout(groupsPerBlock: Int, blocksPerRow: Int) -> GridPattern.Layout {
        var config = WallpaperConfig.default
        config.budget.contentScale = 1.0
        config.budget.groupsPerBlock = groupsPerBlock
        config.budget.blocksPerRow = blocksPerRow
        let composition = Composition(
            config: config,
            canvas: CanvasSpec(pixelWidth: 3840, pixelHeight: 2160, scale: 2, appearance: .dark)
        )
        let progress = TimeModel.Progress(
            mode: .life, elapsed: 2000, total: 4160, todayIndex: 2000, dayKey: "2026-09-09",
            groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10
        )
        return GridPattern.Layout(progress: progress, composition: composition)
    }

    func testTheBlockSizeIsHonoured() {
        let layout = blockLayout(groupsPerBlock: 5, blocksPerRow: 5)
        XCTAssertEqual(layout.rowsPerBlock, 5)
        XCTAssertEqual(layout.blockCount, 16, "80 years in fives")
        XCTAssertEqual(layout.rowCount, 80, "and still eighty rows in total")
    }

    func testBlocksPerRowIsHonoured() {
        XCTAssertEqual(blockLayout(groupsPerBlock: 5, blocksPerRow: 5).blocksAcross, 5)
        XCTAssertEqual(blockLayout(groupsPerBlock: 10, blocksPerRow: 4).blocksAcross, 4)
    }

    func testAnUnevenTilingStillPlacesEveryMark() {
        // 16 blocks five to a row leaves the last row holding one.
        let layout = blockLayout(groupsPerBlock: 5, blocksPerRow: 5)
        let canvas = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        var seen = Set<String>()
        for index in 0 ..< 4160 {
            let center = layout.center(of: index)
            XCTAssertTrue(canvas.contains(center), "index \(index) escaped")
            XCTAssertTrue(
                seen.insert("\(Int(center.x.rounded()))x\(Int(center.y.rounded()))").inserted,
                "index \(index) collides"
            )
        }
    }

    func testAskingForMoreBlocksPerRowThanExistIsClamped() {
        let layout = blockLayout(groupsPerBlock: 10, blocksPerRow: 99)
        XCTAssertEqual(layout.blocksAcross, 8, "there are only eight decades")
        XCTAssertEqual(layout.blocksDown, 1)
    }
}

extension GridLayoutTests {
    /// A year is twelve months in one column. The block knobs exist for a life,
    /// which declares a decade as its major interval; a progress that declares
    /// none must be left alone by them.
    func testAProgressWithoutAMajorIntervalIsOneColumn() {
        var config = WallpaperConfig.default
        config.budget.groupsPerBlock = 5
        config.budget.blocksPerRow = 5
        let composition = Composition(
            config: config,
            canvas: CanvasSpec(pixelWidth: 3840, pixelHeight: 2160, scale: 2, appearance: .dark)
        )
        let sizes = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let progress = TimeModel.Progress(
            mode: .year, elapsed: 250, total: 365, todayIndex: 250, dayKey: "2026-09-10",
            groupSizes: sizes, majorGroupInterval: 0
        )
        let layout = GridPattern.Layout(progress: progress, composition: composition)

        XCTAssertEqual(layout.blocksAcross, 1, "one column")
        XCTAssertEqual(layout.blocksDown, 1)
        XCTAssertEqual(layout.rowsPerBlock, 12, "all twelve months in it")
        XCTAssertEqual(layout.rowCount, 12)

        // And every month still starts at the same left edge.
        let left = layout.center(of: 0).x
        var start = 0
        for (month, length) in sizes.enumerated() {
            XCTAssertEqual(layout.center(of: start).x, left, accuracy: 0.0001, "month \(month + 1)")
            start += length
        }
    }

    /// What the settings bar is placed against: it has to be the marks, not
    /// the area they were allowed to fill.
    func testDrawnBoundsAreExactlyTheMarks() {
        let composition = Composition(
            config: .default,
            canvas: CanvasSpec(pixelWidth: 4112, pixelHeight: 2658, scale: 2, appearance: .dark)
        )
        let progress = TimeModel.Progress(
            mode: .year, elapsed: 100, total: 365, todayIndex: 100, dayKey: "2026-04-11",
            groupSizes: monthLengths
        )
        let bounds = GridPattern().drawnBounds(progress: progress, composition: composition)
        let layout = GridPattern.Layout(progress: progress, composition: composition)
        let radius = layout.radius

        XCTAssertEqual(bounds.minX, layout.center(of: 0).x - radius, accuracy: 0.0001)
        XCTAssertEqual(bounds.minY, layout.center(of: 0).y - radius, accuracy: 0.0001)
        // 31 January and 31 December close the right and bottom edges.
        XCTAssertEqual(bounds.maxX, layout.center(of: 30).x + radius, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxY, layout.center(of: 364).y + radius, accuracy: 0.0001)
        XCTAssertTrue(composition.centredSafeRect.contains(bounds))
    }
}
