import Foundation

/// Starter vegetarian, South-Asian-leaning food database with macros per 100g.
/// Values are reasonable USDA-style approximations for cooked weight — swap in
/// verified figures (USDA FoodData Central / label data) before shipping.
enum FoodDatabase {
    static let paneer = FoodItem(name: "Paneer (cooked)", per100g: .init(calories: 265, proteinG: 18, fatG: 20, carbG: 4))
    static let tofuFirm = FoodItem(name: "Firm Tofu", per100g: .init(calories: 144, proteinG: 15, fatG: 8, carbG: 3))
    static let moongDal = FoodItem(name: "Moong Dal (cooked)", per100g: .init(calories: 105, proteinG: 7, fatG: 0.4, carbG: 18),
                                    prepAheadMinutes: 480, prepInstructions: "Soak 30 min, pressure cook 3 whistles — do the night before.")
    static let chana = FoodItem(name: "Chickpeas (cooked)", per100g: .init(calories: 164, proteinG: 9, fatG: 2.6, carbG: 27),
                                 prepAheadMinutes: 720, prepInstructions: "Soak dry chickpeas overnight, cook next day, or use pre-cooked.")
    static let greekYogurt = FoodItem(name: "Plain Greek Yogurt (2%)", per100g: .init(calories: 73, proteinG: 10, fatG: 2, carbG: 4))
    static let whey = FoodItem(name: "Whey Protein (powder)", per100g: .init(calories: 380, proteinG: 80, fatG: 5, carbG: 8))
    static let peaProtein = FoodItem(name: "Pea Protein (powder)", per100g: .init(calories: 375, proteinG: 80, fatG: 6, carbG: 3))
    static let egg = FoodItem(name: "Whole Egg (if lacto-ovo)", per100g: .init(calories: 143, proteinG: 13, fatG: 10, carbG: 1))
    static let basmatiRice = FoodItem(name: "Basmati Rice (cooked)", per100g: .init(calories: 130, proteinG: 2.7, fatG: 0.3, carbG: 28))
    static let roti = FoodItem(name: "Whole Wheat Roti", per100g: .init(calories: 297, proteinG: 11, fatG: 6, carbG: 50),
                                prepAheadMinutes: 20, prepInstructions: "Roll and cook fresh, or reheat pre-made stack.")
    static let oats = FoodItem(name: "Rolled Oats (dry)", per100g: .init(calories: 379, proteinG: 13, fatG: 7, carbG: 67))
    static let spinach = FoodItem(name: "Spinach (cooked)", per100g: .init(calories: 23, proteinG: 2.9, fatG: 0.4, carbG: 3.6))
    static let mixedVeg = FoodItem(name: "Mixed Sabzi Vegetables", per100g: .init(calories: 60, proteinG: 2.5, fatG: 2, carbG: 9))
    static let almonds = FoodItem(name: "Almonds", per100g: .init(calories: 579, proteinG: 21, fatG: 50, carbG: 22))
    static let peanutButter = FoodItem(name: "Peanut Butter", per100g: .init(calories: 588, proteinG: 25, fatG: 50, carbG: 20))
    static let banana = FoodItem(name: "Banana", per100g: .init(calories: 89, proteinG: 1.1, fatG: 0.3, carbG: 23))
    static let oliveOil = FoodItem(name: "Olive Oil", per100g: .init(calories: 884, proteinG: 0, fatG: 100, carbG: 0))
    static let chickenBreast = FoodItem(name: "Chicken Breast (cooked)", per100g: .init(calories: 165, proteinG: 31, fatG: 3.6, carbG: 0))
    static let salmon = FoodItem(name: "Salmon (cooked)", per100g: .init(calories: 208, proteinG: 20, fatG: 13, carbG: 0))
    static let blackBeans = FoodItem(name: "Black Beans (cooked)", per100g: .init(calories: 132, proteinG: 9, fatG: 0.5, carbG: 24))
    static let potatoes = FoodItem(name: "Potatoes (cooked)", per100g: .init(calories: 87, proteinG: 2, fatG: 0.1, carbG: 20))
    static let feta = FoodItem(name: "Feta", per100g: .init(calories: 264, proteinG: 14, fatG: 21, carbG: 4))
    static let tofuSilken = FoodItem(name: "Silken Tofu", per100g: .init(calories: 55, proteinG: 5, fatG: 3, carbG: 2))

    static let all: [FoodItem] = [paneer, tofuFirm, moongDal, chana, greekYogurt, whey, peaProtein, egg, basmatiRice, roti, oats, spinach, mixedVeg, almonds, peanutButter, banana, oliveOil, chickenBreast, salmon, blackBeans, potatoes, feta, tofuSilken]
}
