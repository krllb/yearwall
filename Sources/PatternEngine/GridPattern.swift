import CoreGraphics
import TimeModel

/// One mark per unit of time on a lattice.
///
/// Deliberately rigid — every mark has the same radius and sits exactly on its
/// lattice position. The lattice is the mark size plus a gap, set separately
/// for columns and rows. When the progress is grouped (a life is 80 years of 52
/// weeks) the lattice breaks into groups, because 4160 undifferentiated marks
/// cannot be read as anything but texture.
public struct GridPattern: Pattern {
    public static let id = "grid"
    public static let displayName = "Grid"

    public init() {}

    public func draw(
        progress: TimeModel.Progress,
        composition: Composition,
        rng: inout SeededRNG,
        into context: CGContext
    ) {
        let total = max(progress.total, 1)
        let layout = Layout(progress: progress, composition: composition)
        let radius = layout.radius
        let elapsed = composition.colors.elapsed
        let remaining = composition.colors.remaining

        if composition.config.connectsElapsedMarks {
            // Under the marks, so they still bulge through the line.
            strikeElapsedRuns(progress: progress, layout: layout, radius: radius,
                              colour: elapsed, composition: composition, into: context)
            context.setFill(elapsed)
            for index in 0 ..< total {
                context.fillCircle(center: layout.center(of: index), radius: radius)
            }
            return
        }

        for index in 0 ..< total {
            let center = layout.center(of: index)
            switch MarkKind(index: index, progress: progress) {
            case .elapsed, .today:
                context.setFill(elapsed)
            case .remaining:
                context.setFill(remaining)
            }
            context.fillCircle(center: center, radius: radius)
        }
    }

    /// Exactly the marks: the strike through them is no wider than a mark.
    public func drawnBounds(progress: TimeModel.Progress, composition: Composition) -> CGRect {
        let layout = Layout(progress: progress, composition: composition)
        let radius = layout.radius
        var bounds = CGRect.null
        for index in 0 ..< max(progress.total, 1) {
            let center = layout.center(of: index)
            bounds = bounds.union(CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
            ))
        }
        return bounds
    }

    /// One line per row, from the row's first mark to its last elapsed one.
    ///
    /// Drawn per row rather than as one polyline: a line that jumped from the
    /// end of one row to the start of the next would cut diagonally across the
    /// whole block.
    private func strikeElapsedRuns(
        progress: TimeModel.Progress,
        layout: Layout,
        radius: CGFloat,
        colour: RGBA,
        composition: Composition,
        into context: CGContext
    ) {
        let lastUsed = progress.todayIndex
        guard lastUsed >= 0 else { return }

        let width = max(1, radius * 2 * CGFloat(composition.budget.connectorWidth))
        context.setStroke(colour)
        context.setLineWidth(width)
        context.setLineCap(.round)

        for row in 0 ..< layout.rowCount {
            let range = layout.rowRange(row)
            guard let first = range.first, first <= lastUsed else { continue }
            let last = min(range.upperBound - 1, lastUsed)
            guard last > first else { continue }

            context.beginPath()
            context.move(to: layout.center(of: first))
            context.addLine(to: layout.center(of: last))
            context.strokePath()
        }
    }

    /// Where each of `total` marks goes.
    ///
    /// The drawing is as big as its marks and gaps make it — `maxMarkSizePoints`
    /// across each mark, `columnGapPoints` and `rowGapPoints` between them —
    /// centred on the canvas. It is scaled down, marks and gaps together, only
    /// when that would not fit between the menu bar and the Dock.
    ///
    /// **Grouped**: a group is a row — the weeks of a year, or the days of a
    /// month — read left to right, groups stacked top to bottom in the order
    /// time passes. Every row is as wide as the longest group and shorter rows
    /// simply end early, so February's row is three cells shorter than March's
    /// and the ragged right edge is the point rather than a defect.
    ///
    /// When a major interval is set, a run of that many groups is a block, and
    /// the blocks are tiled across the canvas and wrapped:
    ///
    ///     [ 1-10 ] [ 11-20 ]
    ///     [21-30 ] [ 31-40 ]
    ///     ...
    ///
    /// The tiling is chosen by trying every arrangement and keeping the one
    /// that has to shrink the least, so it follows the canvas shape rather than
    /// a fixed guess.
    ///
    /// **Ungrouped**, two things matter:
    ///
    /// * A column count that divides `total` exactly beats one that fits the
    ///   screen's aspect ratio better. 365 days is 5 x 73 and nothing else, so
    ///   a year has to live with a stub row.
    /// * The stub is left-aligned — it is the tail of a run, not a caption —
    ///   and the block is centred counting the stub as the fraction of a row it
    ///   actually is, so a nearly-empty last row does not drag it upwards.
    struct Layout {
        /// Marks per row: 52, for the weeks of a year.
        let acrossCount: Int
        /// Rows in one block: a decade, for a life.
        let rowsPerBlock: Int
        /// Blocks per block-row.
        let blocksAcross: Int
        /// Rows of blocks.
        let blocksDown: Int
        /// Blocks that actually hold marks. A tiling can offer more slots than
        /// there are blocks — 16 blocks in a 5-wide grid leaves four empty.
        let blockCount: Int
        /// Rows that actually hold marks, across every block.
        let rowCount: Int
        /// Mark radius, in pixels, after any shrinking to fit.
        let radius: CGFloat
        /// Centre to centre: `width` between columns, `height` between rows.
        let pitch: CGSize
        /// Top-left corner of the first mark's bounding box.
        let origin: CGPoint
        /// Distance from one block's top-left corner to the next block's.
        let blockStride: CGSize
        /// How many marks the layout was built for.
        let total: Int
        /// Ungrouped only: how many marks the last, partial row holds.
        let remainder: Int
        /// Grouped only: the first unit of each group, for placing a mark.
        let groupStarts: [Int]

        init(progress: TimeModel.Progress, composition: Composition) {
            let area = composition.centredSafeRect
            let metrics = Metrics(budget: composition.budget, scale: CGFloat(composition.scale))

            guard progress.hasGroups else {
                self = Layout(plainTotal: max(progress.total, 1), in: area, metrics: metrics)
                return
            }
            self = Layout(grouped: progress, in: area, metrics: metrics, budget: composition.budget)
        }

        /// Mark and gaps in pixels, at their natural size.
        struct Metrics {
            let diameter: CGFloat
            let gap: CGSize

            init(budget: CompositionBudget, scale: CGFloat) {
                diameter = max(CGFloat(budget.maxMarkSizePoints) * scale, 1)
                gap = CGSize(
                    width: max(CGFloat(budget.columnGapPoints), 0) * scale,
                    height: max(CGFloat(budget.rowGapPoints), 0) * scale
                )
            }

            var pitch: CGSize {
                CGSize(width: diameter + gap.width, height: diameter + gap.height)
            }

            /// From the first mark's outer edge to the last one's, `count` marks
            /// along one axis.
            func span(_ count: Int, pitch: CGFloat) -> CGFloat {
                CGFloat(max(count, 1) - 1) * pitch + diameter
            }
        }

        // MARK: Grouped

        private init(
            grouped progress: TimeModel.Progress,
            in area: CGRect,
            metrics: Metrics,
            budget: CompositionBudget
        ) {
            let across = progress.widestGroup
            let groups = progress.groupCount
            let major = progress.majorGroupInterval

            // Only a progress that declares a major interval gets split into
            // blocks at all. A year is twelve months and reads as one column;
            // chopping it into blocks of five months says nothing about a year.
            // Within a progress that does declare one — a life, by decade —
            // `groupsPerBlock` may override the size.
            let rowsPerBlock: Int
            if major > 1 {
                let requested = budget.groupsPerBlock > 0 ? budget.groupsPerBlock : major
                rowsPerBlock = min(max(requested, 1), groups)
            } else {
                rowsPerBlock = groups
            }
            let blocks = (groups + rowsPerBlock - 1) / rowsPerBlock

            let pitch = metrics.pitch
            let block = CGSize(
                width: metrics.span(across, pitch: pitch.width),
                height: metrics.span(rowsPerBlock, pitch: pitch.height)
            )
            let blockGap = CGSize(
                width: CGFloat(max(budget.blockGap, 0)) * pitch.width,
                height: CGFloat(max(budget.blockGap, 0)) * pitch.height
            )

            // Try every tiling and keep the one that has to shrink the least,
            // unless a specific number of blocks per row was asked for.
            let candidates: [Int] = budget.blocksPerRow > 0
                ? [min(budget.blocksPerRow, max(blocks, 1))]
                : Array(1 ... max(blocks, 1))

            var best: (acrossBlocks: Int, downBlocks: Int, fit: CGFloat)?
            for acrossBlocks in candidates {
                let downBlocks = (blocks + acrossBlocks - 1) / acrossBlocks
                // No block-row may end up empty.
                if (downBlocks - 1) * acrossBlocks >= blocks, blocks > 0, downBlocks > 1 { continue }

                let width = CGFloat(acrossBlocks) * block.width + CGFloat(acrossBlocks - 1) * blockGap.width
                let height = CGFloat(downBlocks) * block.height + CGFloat(downBlocks - 1) * blockGap.height
                let fit = min(area.width / width, area.height / height, 1)
                if best == nil || fit > best!.fit {
                    best = (acrossBlocks, downBlocks, fit)
                }
            }

            let chosen = best ?? (1, blocks, 1)
            let fit = chosen.fit
            let stride = CGSize(
                width: (block.width + blockGap.width) * fit,
                height: (block.height + blockGap.height) * fit
            )
            let width = stride.width * CGFloat(chosen.acrossBlocks) - blockGap.width * fit
            let height = stride.height * CGFloat(chosen.downBlocks) - blockGap.height * fit

            self.acrossCount = across
            self.rowsPerBlock = rowsPerBlock
            self.blocksAcross = chosen.acrossBlocks
            self.blocksDown = chosen.downBlocks
            self.blockCount = blocks
            self.rowCount = groups
            self.radius = metrics.diameter * fit / 2
            self.pitch = CGSize(width: pitch.width * fit, height: pitch.height * fit)
            self.blockStride = stride
            self.total = progress.total
            self.remainder = 0
            self.groupStarts = progress.groupStarts
            self.origin = CGPoint(x: area.midX - width / 2, y: area.midY - height / 2)
        }

        // MARK: Ungrouped

        private init(plainTotal total: Int, in area: CGRect, metrics: Metrics) {
            let pitch = metrics.pitch
            // Columns such that the block's shape follows the area's, allowing
            // for rows and columns being spaced differently.
            let aspect = Double(area.width / max(area.height, 1)) * Double(pitch.height / pitch.width)
            let ideal: Double = (Double(total) * aspect).squareRoot()
            let columns = Self.columnCount(total: total, ideal: ideal)

            let fullRows = total / columns
            let remainder = total % columns
            let rows = fullRows + (remainder > 0 ? 1 : 0)

            let width = metrics.span(columns, pitch: pitch.width)
            let height = metrics.span(rows, pitch: pitch.height)
            let fit = min(area.width / width, area.height / height, 1)

            // The block is centred on how much of the grid is filled, so a
            // nearly-empty stub row does not drag it upwards.
            let filledRows = CGFloat(fullRows) + CGFloat(remainder) / CGFloat(columns)
            let filledHeight = (filledRows - 1) * pitch.height + metrics.diameter

            self.acrossCount = columns
            self.rowsPerBlock = rows
            self.blocksAcross = 1
            self.blocksDown = 1
            self.blockCount = 1
            self.rowCount = rows
            self.radius = metrics.diameter * fit / 2
            self.pitch = CGSize(width: pitch.width * fit, height: pitch.height * fit)
            self.blockStride = CGSize(width: width * fit, height: height * fit)
            self.total = total
            self.remainder = remainder
            self.groupStarts = []
            self.origin = CGPoint(
                x: area.midX - width * fit / 2,
                y: area.midY - filledHeight * fit / 2
            )
        }

        /// Prefer an exact divisor of `total` near `ideal`; otherwise `ideal`.
        static func columnCount(total: Int, ideal: Double) -> Int {
            let rounded = max(1, min(Int(ideal.rounded()), total))
            let window = max(2, Int((ideal * 0.25).rounded()))
            let lower = max(1, rounded - window)
            let upper = min(total, rounded + window)

            var best: Int?
            for candidate in lower ... upper where total % candidate == 0 {
                if let current = best,
                   abs(Double(current) - ideal) <= abs(Double(candidate) - ideal) {
                    continue
                }
                best = candidate
            }
            return best ?? rounded
        }

        // MARK: Placement

        func center(of index: Int) -> CGPoint {
            let row: Int
            let across: Int
            if groupStarts.isEmpty {
                // Ungrouped: rows of `acrossCount`, the last one left-aligned
                // like every other.
                row = index / acrossCount
                across = index % acrossCount
            } else {
                let placed = position(of: index)
                row = placed.group
                across = placed.offset
            }

            let block = row / rowsPerBlock
            let rowInBlock = row % rowsPerBlock
            // Blocks read left to right, then wrap to the next block-row.
            let blockColumn = block % blocksAcross
            let blockRow = block / blocksAcross

            return CGPoint(
                x: origin.x + CGFloat(blockColumn) * blockStride.width + CGFloat(across) * pitch.width + radius,
                y: origin.y + CGFloat(blockRow) * blockStride.height + CGFloat(rowInBlock) * pitch.height + radius
            )
        }

        /// The marks that make up one row.
        func rowRange(_ row: Int) -> Range<Int> {
            if groupStarts.isEmpty {
                let start = row * acrossCount
                return start ..< min(start + acrossCount, total)
            }
            guard row + 1 < groupStarts.count else { return 0 ..< 0 }
            return groupStarts[row] ..< groupStarts[row + 1]
        }

        /// Which group a unit falls in, and how far into it.
        private func position(of unit: Int) -> (group: Int, offset: Int) {
            var low = 0
            var high = groupStarts.count - 2
            while low < high {
                let mid = (low + high + 1) / 2
                if groupStarts[mid] <= unit { low = mid } else { high = mid - 1 }
            }
            return (low, unit - groupStarts[low])
        }
    }
}
