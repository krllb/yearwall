import CoreGraphics
import Foundation

/// Every number that makes the output behave like a *wallpaper* rather than a
/// poster lives here, so it can be tuned in one place (and, later, exposed in
/// settings) instead of being scattered through the patterns.
public struct CompositionBudget: Sendable, Equatable, Codable {
    // MARK: Contrast

    /// Hard cap on how far any non-accent mark may travel from the background
    /// colour. 0.55 == "55% of the way to full ink".
    public var maxPatternContrast: Double
    /// The single "today" mark is the exception, and it is the only one.
    public var accentContrast: Double

    // MARK: Safe insets (points, converted with the canvas scale)

    /// Menu bar. 24pt on most Macs, ~37pt on notched ones; 40 covers both.
    public var menuBarInsetPoints: Double
    /// The *actual* height of the menu bar, as opposed to the generous inset
    /// above. Measured from the screen and only used to size the blackout band,
    /// which has to line up with the real bar rather than clear it.
    public var menuBarBandPoints: Double
    /// Dock, generously: it grows with magnification.
    public var dockInsetPoints: Double
    /// Side margins as a fraction of canvas width.
    public var horizontalInsetFraction: Double
    /// The **most** of the safe rect the drawing may occupy. It is a ceiling,
    /// not a target: the drawing grows only until its marks reach
    /// `maxMarkSizePoints`, so a sparse mode stays compact instead of spreading
    /// the same few marks across the whole screen.
    ///
    /// Phyllotaxis only. The grid is as big as its marks and gaps make it.
    public var contentScale: Double

    // MARK: Mark geometry

    /// Radius of a dot as a fraction of the local spacing.
    public var dotFill: Double
    /// A mark's diameter, in points.
    ///
    /// The grid draws exactly this, and shrinks only when the drawing would
    /// not fit on the screen. Phyllotaxis treats it as a ceiling: past it the
    /// marks stop growing however much room they have.
    public var maxMarkSizePoints: Double
    /// Space between neighbouring marks in a grid row, edge to edge, in points.
    public var columnGapPoints: Double
    /// Space between grid rows, edge to edge, in points. A year's rows are
    /// its months.
    public var rowGapPoints: Double
    /// Gap at every `majorGroupInterval`-th boundary — decades, for a life.
    public var majorGroupGap: Double
    /// How many groups make one block. 0 means "use the progress's own major
    /// interval" — decades, for a life.
    public var groupsPerBlock: Int
    /// How many blocks to put in a row. 0 means "try every arrangement and keep
    /// whichever leaves room for the largest cell".
    public var blocksPerRow: Int
    /// Gap between blocks, in grid pitches (mark plus gap) along each axis.
    /// Wide enough that a block reads as a block and not as a wider week.
    public var blockGap: Double
    /// How much bigger the "today" mark is than a normal one.
    public var accentScale: Double
    /// Thickness of the line struck through an elapsed run, as a fraction of
    /// a mark's diameter.
    ///
    /// 1.0 makes the line exactly as thick as a mark, so with round caps the
    /// run becomes one smooth bar. Anything less leaves the marks bulging out
    /// of a thinner line, which reads as a caterpillar rather than as a run.
    public var connectorWidth: Double
    /// How strong a mark for a unit still ahead is, relative to one already
    /// behind us. Every mark is filled; only the weight differs.
    ///
    /// Outlining the future ones was tried first. At the sizes these marks
    /// actually get, a one-pixel ring is not reliably distinguishable from a
    /// filled dot, and the drawing read as two unrelated textures rather than
    /// one run of time.
    public var remainingIntensity: Double

    public init(
        maxPatternContrast: Double = 0.55,
        accentContrast: Double = 1.0,
        menuBarInsetPoints: Double = 40,
        menuBarBandPoints: Double = 24,
        dockInsetPoints: Double = 100,
        horizontalInsetFraction: Double = 0.05,
        contentScale: Double = 0.85,
        dotFill: Double = 0.30,
        maxMarkSizePoints: Double = 10.0,
        columnGapPoints: Double = 6,
        rowGapPoints: Double = 16,
        majorGroupGap: Double = 1.1,
        groupsPerBlock: Int = 5,
        blocksPerRow: Int = 4,
        blockGap: Double = 2.2,
        accentScale: Double = 1.7,
        remainingIntensity: Double = 0.30,
        connectorWidth: Double = 1.0
    ) {
        self.maxPatternContrast = maxPatternContrast
        self.accentContrast = accentContrast
        self.menuBarInsetPoints = menuBarInsetPoints
        self.menuBarBandPoints = menuBarBandPoints
        self.dockInsetPoints = dockInsetPoints
        self.horizontalInsetFraction = horizontalInsetFraction
        self.contentScale = contentScale
        self.dotFill = dotFill
        self.maxMarkSizePoints = maxMarkSizePoints
        self.columnGapPoints = columnGapPoints
        self.rowGapPoints = rowGapPoints
        self.majorGroupGap = majorGroupGap
        self.groupsPerBlock = groupsPerBlock
        self.blocksPerRow = blocksPerRow
        self.blockGap = blockGap
        self.accentScale = accentScale
        self.remainingIntensity = remainingIntensity
        self.connectorWidth = connectorWidth
    }

    public static let `default` = CompositionBudget()

    /// Every field falls back independently, so a config written by another
    /// build still loads.
    public init(from decoder: any Decoder) throws {
        let fallback = CompositionBudget()
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = fallback
            return
        }
        self.init(
            maxPatternContrast: container.lenient(.maxPatternContrast, fallback.maxPatternContrast),
            accentContrast: container.lenient(.accentContrast, fallback.accentContrast),
            menuBarInsetPoints: container.lenient(.menuBarInsetPoints, fallback.menuBarInsetPoints),
            menuBarBandPoints: container.lenient(.menuBarBandPoints, fallback.menuBarBandPoints),
            dockInsetPoints: container.lenient(.dockInsetPoints, fallback.dockInsetPoints),
            horizontalInsetFraction: container.lenient(.horizontalInsetFraction, fallback.horizontalInsetFraction),
            contentScale: container.lenient(.contentScale, fallback.contentScale),
            dotFill: container.lenient(.dotFill, fallback.dotFill),
            maxMarkSizePoints: container.lenient(.maxMarkSizePoints, fallback.maxMarkSizePoints),
            columnGapPoints: container.lenient(.columnGapPoints, fallback.columnGapPoints),
            rowGapPoints: container.lenient(.rowGapPoints, fallback.rowGapPoints),
            majorGroupGap: container.lenient(.majorGroupGap, fallback.majorGroupGap),
            groupsPerBlock: container.lenient(.groupsPerBlock, fallback.groupsPerBlock),
            blocksPerRow: container.lenient(.blocksPerRow, fallback.blocksPerRow),
            blockGap: container.lenient(.blockGap, fallback.blockGap),
            accentScale: container.lenient(.accentScale, fallback.accentScale),
            remainingIntensity: container.lenient(.remainingIntensity, fallback.remainingIntensity),
            connectorWidth: container.lenient(.connectorWidth, fallback.connectorWidth)
        )
    }

}
