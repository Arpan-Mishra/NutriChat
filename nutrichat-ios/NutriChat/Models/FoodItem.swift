import Foundation

/// Food item as returned by the food search API.
struct FoodItem: Codable, Identifiable {
    let id: Int
    let name: String
    var brand: String?
    var barcode: String?
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    let carbsPer100g: Double
    var fiberPer100g: Double?
    var sodiumPer100g: Double?
    var servingSizeG: Double?
    var servingDescription: String?
    let source: String
    var isIndian: Bool?
    var verified: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, brand, barcode, source, verified
        case caloriesPer100g = "calories_per_100g"
        case proteinPer100g = "protein_per_100g"
        case fatPer100g = "fat_per_100g"
        case carbsPer100g = "carbs_per_100g"
        case fiberPer100g = "fiber_per_100g"
        case sodiumPer100g = "sodium_per_100g"
        case servingSizeG = "serving_size_g"
        case servingDescription = "serving_description"
        case isIndian = "is_indian"
    }

    /// Compute macros for a given serving size in grams.
    func macros(forServingG grams: Double) -> (calories: Double, protein: Double, fat: Double, carbs: Double) {
        let factor = grams / 100.0
        return (
            calories: caloriesPer100g * factor,
            protein: proteinPer100g * factor,
            fat: fatPer100g * factor,
            carbs: carbsPer100g * factor
        )
    }
}
