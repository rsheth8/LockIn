import XCTest
import UIKit
@testable import LockIn

/// Covers reading a Nutrition Facts panel.
///
/// Split deliberately in two. `parse` is tested against hand-written rows,
/// which pins the regex behaviour exactly and runs instantly; then one
/// end-to-end test renders a real panel and puts it through Vision, because a
/// parser that's perfect on clean strings is worthless if the row grouping
/// upstream of it hands over garbage.
final class NutritionLabelParsingTests: XCTestCase {

    /// The current US FDA panel, as Vision typically returns it after the
    /// two-column runs have been regrouped into rows.
    private let fdaPanel = [
        "Nutrition Facts",
        "8 servings per container",
        "Serving size 2/3 cup (55g)",
        "Amount per serving",
        "Calories 230",
        "% Daily Value*",
        "Total Fat 8g 10%",
        "Saturated Fat 1g 5%",
        "Trans Fat 0g",
        "Cholesterol 0mg 0%",
        "Sodium 160mg 7%",
        "Total Carbohydrate 37g 13%",
        "Dietary Fiber 4g 14%",
        "Total Sugars 12g",
        "Protein 3g"
    ]

    func testReadsEveryMacroFromAStandardPanel() {
        let reading = NutritionLabelReader.parse(rows: fdaPanel)

        XCTAssertEqual(reading.calories, 230)
        XCTAssertEqual(reading.fat, 8)
        XCTAssertEqual(reading.carbs, 37)
        XCTAssertEqual(reading.protein, 3)
        XCTAssertEqual(reading.servingGrams, 55)
        XCTAssertEqual(reading.foundCount, 4)
        XCTAssertTrue(reading.isUsable)
    }

    /// Every macro row ends in a % Daily Value. Matching a bare number instead
    /// of one with a `g` would read "Total Fat 8g 10%" as 10 g of fat — a
    /// silent 25% calorie error on a typical label.
    func testDailyValuePercentagesAreNotMistakenForGrams() {
        let reading = NutritionLabelReader.parse(rows: fdaPanel)

        XCTAssertEqual(reading.fat, 8, "must take the grams, not the 10% daily value")
        XCTAssertEqual(reading.carbs, 37, "must take the grams, not the 13% daily value")
    }

    /// "Saturated Fat" and "Trans Fat" both sit below "Total Fat" and both
    /// match a naive search for "fat".
    func testSaturatedAndTransFatDoNotClaimTheFatSlot() {
        let reading = NutritionLabelReader.parse(rows: [
            "Calories 180",
            "Total Fat 12g 15%",
            "Saturated Fat 7g 35%",
            "Trans Fat 0g",
            "Protein 5g"
        ])

        XCTAssertEqual(reading.fat, 12)
    }

    /// A panel with no "Total Fat" line at all — common outside the US — should
    /// still resolve, but only after the strict pass has failed.
    func testFallsBackToBareFatOnlyWhenTotalFatIsAbsent() {
        let reading = NutritionLabelReader.parse(rows: [
            "Energy 250 kcal",
            "Calories 250",
            "Saturated Fat 3g",
            "Fat 9g",
            "Carbohydrate 20g",
            "Protein 15g"
        ])

        XCTAssertEqual(reading.fat, 9, "the bare Fat line wins over the saturated one")
        XCTAssertEqual(reading.carbs, 20)
        XCTAssertEqual(reading.protein, 15)
    }

    /// Older panels carry "Calories from Fat" directly beneath the calorie
    /// figure. Taking the later match would under-report the meal.
    func testCaloriesFromFatDoesNotOverwriteCalories() {
        let reading = NutritionLabelReader.parse(rows: [
            "Calories 250",
            "Calories from Fat 110",
            "Total Fat 12g",
            "Protein 5g"
        ])

        XCTAssertEqual(reading.calories, 250)
    }

    /// The single most common OCR failure on these panels: a zero read as the
    /// letter O. Left unrepaired it turns "0g" into no reading at all, which
    /// silently drops a macro rather than failing visibly.
    func testRepairsZerosMisreadAsTheLetterO() {
        let reading = NutritionLabelReader.parse(rows: [
            "Calories 90",
            "Total Fat Og",
            "Total Carbohydrate 1Og",
            "Protein 21g"
        ])

        XCTAssertEqual(reading.fat, 0, "\"Og\" is a misread zero, not a missing value")
        XCTAssertEqual(reading.carbs, 10)
    }

    /// A partial read is the normal outcome on a crumpled pouch. It must
    /// surface as "3 of 4 found" rather than zeros the user might accept.
    func testPartialReadIsReportedRatherThanZeroFilled() {
        let reading = NutritionLabelReader.parse(rows: [
            "Calories 200",
            "Total Fat 10g",
            "Protein 8g"
        ])

        XCTAssertEqual(reading.foundCount, 3)
        XCTAssertNil(reading.carbs, "an unread macro must stay nil, not become 0")
        XCTAssertTrue(reading.isUsable)
    }

    /// No calories means nothing to log. A form of zeros invites the user to
    /// accept them.
    func testUnreadableLabelIsNotUsable() {
        let reading = NutritionLabelReader.parse(rows: ["INGREDIENTS: WATER, SUGAR", "Distributed by"])

        XCTAssertFalse(reading.isUsable)
        XCTAssertEqual(reading.foundCount, 0)
    }

    func testServingSizeTextAndGramsAreBothCaptured() {
        let reading = NutritionLabelReader.parse(rows: ["Serving size 1 bar (40g)", "Calories 190"])

        XCTAssertEqual(reading.servingGrams, 40)
        XCTAssertEqual(reading.servingText, "1 bar (40g)")
    }

    func testDecimalGramsSurvive() {
        let reading = NutritionLabelReader.parse(rows: ["Calories 120", "Total Fat 2.5g", "Protein 3g"])

        XCTAssertEqual(reading.fat, 2.5)
    }
}

/// End-to-end: a rendered panel through Vision and out the other side.
///
/// The parser tests above all assume the row grouping worked. This is the test
/// that would catch it not working — Vision returns "Total Fat" and "8g" as
/// separate observations, and without regrouping them by vertical position
/// every macro reads as nil while the parser itself stays green.
final class NutritionLabelOCRTests: XCTestCase {

    func testReadsARenderedPanelEndToEnd() async throws {
        let image = Self.renderPanel()
        let reading = try await NutritionLabelReader.read(image)

        XCTAssertTrue(reading.isUsable, "Vision should read a cleanly rendered panel")
        XCTAssertEqual(reading.calories, 230, "calories are the one field worth blocking on")
        XCTAssertEqual(reading.fat, 8)
        XCTAssertEqual(reading.carbs, 37)
        XCTAssertEqual(reading.protein, 3)
    }

    /// Two-column layout, drawn the way a real panel is: the nutrient name on
    /// the left and its value on the right, far enough apart that Vision emits
    /// them as separate text observations.
    private static func renderPanel() -> UIImage {
        let size = CGSize(width: 640, height: 820)
        let rows: [(String, String)] = [
            ("Nutrition Facts", ""),
            ("Serving size", "2/3 cup (55g)"),
            ("Calories", "230"),
            ("Total Fat", "8g"),
            ("Saturated Fat", "1g"),
            ("Trans Fat", "0g"),
            ("Sodium", "160mg"),
            ("Total Carbohydrate", "37g"),
            ("Dietary Fiber", "4g"),
            ("Protein", "3g")
        ]

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = 40
            for (label, value) in rows {
                let bold = label == "Nutrition Facts" || label == "Calories"
                let font = UIFont.systemFont(ofSize: bold ? 40 : 28, weight: bold ? .bold : .regular)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: UIColor.black
                ]
                label.draw(at: CGPoint(x: 36, y: y), withAttributes: attributes)

                if !value.isEmpty {
                    let width = (value as NSString).size(withAttributes: attributes).width
                    value.draw(at: CGPoint(x: size.width - 36 - width, y: y), withAttributes: attributes)
                }
                y += font.lineHeight + 22
            }
        }
    }
}
