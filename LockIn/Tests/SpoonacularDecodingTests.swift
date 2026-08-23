import XCTest
@testable import LockIn

/// Decoding is pinned against payloads captured from the live Spoonacular API
/// rather than hand-written shapes, so a wrong assumption about the wire format
/// fails here instead of silently producing zeroed macros in the app.
final class SpoonacularDecodingTests: XCTestCase {

    /// Trimmed from a real `/recipes/complexSearch?addRecipeNutrition=true`
    /// response. Extra fields are intentionally left in to prove the decoder
    /// tolerates them.
    private let liveSearchJSON = """
    {
      "results": [
        {
          "id": 635964,
          "image": "bread-omlette-635964.jpg",
          "imageType": "jpg",
          "title": "Bread Omlette",
          "readyInMinutes": 45,
          "servings": 1,
          "sourceUrl": "https://www.foodista.com/recipe/2M6MVKZT/bread-omlette",
          "vegetarian": true,
          "vegan": false,
          "nutrition": {
            "nutrients": [
              { "name": "Calories", "amount": 824.68, "unit": "kcal", "percentOfDailyNeeds": 41.23 },
              { "name": "Fat", "amount": 30.27, "unit": "g", "percentOfDailyNeeds": 46.57 },
              { "name": "Carbohydrates", "amount": 90.4, "unit": "g", "percentOfDailyNeeds": 30.13 },
              { "name": "Protein", "amount": 44.6, "unit": "g", "percentOfDailyNeeds": 89.19 }
            ],
            "caloricBreakdown": { "percentProtein": 21.4 }
          }
        }
      ],
      "offset": 0,
      "number": 1,
      "totalResults": 94
    }
    """.data(using: .utf8)!

    func testDecodesLiveSearchResponse() throws {
        let response = try JSONDecoder().decode(SpoonacularSearchResponse.self, from: liveSearchJSON)
        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.totalResults, 94)

        let recipe = response.results[0]
        XCTAssertEqual(recipe.id, 635964)
        XCTAssertEqual(recipe.title, "Bread Omlette")
        XCTAssertEqual(recipe.readyInMinutes, 45)
    }

    func testExtractsMacrosFromTheNamedNutrientArray() throws {
        let response = try JSONDecoder().decode(SpoonacularSearchResponse.self, from: liveSearchJSON)
        let macros = response.results[0].macrosPerServing

        XCTAssertEqual(macros.calories, 824.68, accuracy: 0.01)
        XCTAssertEqual(macros.proteinG, 44.6, accuracy: 0.01)
        XCTAssertEqual(macros.fatG, 30.27, accuracy: 0.01)
        XCTAssertEqual(macros.carbG, 90.4, accuracy: 0.01)
    }

    func testNutrientLookupIsCaseInsensitive() throws {
        let nutrition = SpoonacularRecipe.Nutrition(nutrients: [
            .init(name: "CALORIES", amount: 500, unit: "kcal")
        ])
        XCTAssertEqual(nutrition.amount(of: "Calories"), 500)
    }

    func testMissingNutrientReturnsZeroRatherThanCrashing() {
        let nutrition = SpoonacularRecipe.Nutrition(nutrients: [])
        XCTAssertEqual(nutrition.amount(of: "Protein"), 0)
    }

    func testRecipeWithoutNutritionYieldsZeroedMacros() {
        let recipe = SpoonacularRecipe(id: 1, title: "x", readyInMinutes: nil,
                                       servings: nil, sourceUrl: nil, nutrition: nil)
        XCTAssertEqual(recipe.macrosPerServing.calories, 0)
        XCTAssertEqual(recipe.macrosPerServing.proteinG, 0)
    }

    func testPrepAheadThresholdIsThirtyMinutes() {
        XCTAssertTrue(Fixture.recipe(id: 1, calories: 400, protein: 30, minutes: 45).needsPrepAhead)
        XCTAssertFalse(Fixture.recipe(id: 2, calories: 400, protein: 30, minutes: 30).needsPrepAhead)
        XCTAssertFalse(Fixture.recipe(id: 3, calories: 400, protein: 30, minutes: 5).needsPrepAhead)
    }

    func testRecipeSurvivesEncodeDecodeForCaching() throws {
        let original = Fixture.recipePool
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode([SpoonacularRecipe].self, from: data)

        XCTAssertEqual(restored.map(\.id), original.map(\.id))
        XCTAssertEqual(restored[0].macrosPerServing.proteinG, original[0].macrosPerServing.proteinG)
    }

    // MARK: - Ingredient measures

    func testIngredientGramsParsedFromMetricMeasure() throws {
        let json = """
        { "id": 1, "title": "t", "readyInMinutes": 10, "servings": 2, "sourceUrl": null,
          "extendedIngredients": [
            { "id": 9, "name": "paneer", "amount": 1, "unit": "cup",
              "measures": { "metric": { "amount": 226.0, "unitShort": "g" } } },
            { "id": 10, "name": "milk", "amount": 1, "unit": "cup",
              "measures": { "metric": { "amount": 240.0, "unitShort": "ml" } } },
            { "id": 11, "name": "pinch", "amount": 1, "unit": "pinch",
              "measures": { "metric": { "amount": 1.0, "unitShort": "pinch" } } }
          ] }
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(SpoonacularRecipeDetail.self, from: json)
        let ingredients = try XCTUnwrap(detail.extendedIngredients)

        XCTAssertEqual(ingredients[0].grams, 226)
        XCTAssertEqual(ingredients[1].grams, 240, "ml is treated as grams for liquids")
        XCTAssertNil(ingredients[2].grams, "Non-mass units must not be guessed at")
    }

    // MARK: - Diet parameter mapping

    func testDietaryPatternMapsToSpoonacularParameter() {
        XCTAssertEqual(DietaryPattern.vegetarian.spoonacularDiet, "vegetarian")
        XCTAssertEqual(DietaryPattern.vegan.spoonacularDiet, "vegan")
        XCTAssertEqual(DietaryPattern.pescatarian.spoonacularDiet, "pescetarian",
                       "Spoonacular spells it 'pescetarian'")
        XCTAssertNil(DietaryPattern.omnivore.spoonacularDiet, "Omnivore must not constrain the search")
    }

    func testCuisinePreferenceMapsToSpoonacularParameter() {
        XCTAssertEqual(CuisinePreference.southAsian.spoonacularCuisine, "Indian")
        XCTAssertNil(CuisinePreference.noPreference.spoonacularCuisine)
    }
}
