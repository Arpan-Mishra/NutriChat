"""Seed script for common Indian foods based on IFCT (Indian Food Composition Tables) data.

Data sourced from National Institute of Nutrition (NIN), Hyderabad.
Values are per 100g of edible portion.

Run: cd backend && python -m scripts.seed_indian_foods
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import SessionLocal, engine, Base
from app.models import FoodItem

# fmt: off
INDIAN_FOODS = [
    # --- Cereals & Grains ---
    {"name": "Rice, white, cooked", "cal": 130, "pro": 2.7, "fat": 0.3, "carb": 28.2, "fiber": 0.4, "serving": "1 cup (158g)", "serving_g": 158},
    {"name": "Rice, brown, cooked", "cal": 123, "pro": 2.7, "fat": 1.0, "carb": 25.6, "fiber": 1.8, "serving": "1 cup (158g)", "serving_g": 158},
    {"name": "Wheat flour, whole (atta)", "cal": 341, "pro": 12.1, "fat": 1.7, "carb": 71.2, "fiber": 11.2, "serving": "100g", "serving_g": 100},
    {"name": "Roti / Chapati", "cal": 240, "pro": 8.7, "fat": 3.7, "carb": 44.0, "fiber": 4.0, "serving": "1 roti (40g)", "serving_g": 40},
    {"name": "Naan", "cal": 290, "pro": 8.9, "fat": 5.6, "carb": 50.0, "fiber": 2.1, "serving": "1 naan (90g)", "serving_g": 90},
    {"name": "Paratha, plain", "cal": 326, "pro": 7.4, "fat": 13.7, "carb": 44.3, "fiber": 3.5, "serving": "1 paratha (80g)", "serving_g": 80},
    {"name": "Poha (flattened rice), cooked", "cal": 110, "pro": 2.0, "fat": 2.5, "carb": 21.0, "fiber": 0.5, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Upma, cooked", "cal": 105, "pro": 3.0, "fat": 3.5, "carb": 16.0, "fiber": 1.0, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Dosa, plain", "cal": 168, "pro": 3.9, "fat": 3.7, "carb": 29.4, "fiber": 0.8, "serving": "1 dosa (85g)", "serving_g": 85},
    {"name": "Idli", "cal": 130, "pro": 3.9, "fat": 0.4, "carb": 26.5, "fiber": 0.9, "serving": "1 idli (60g)", "serving_g": 60},
    {"name": "Puri", "cal": 350, "pro": 7.0, "fat": 16.0, "carb": 44.0, "fiber": 2.5, "serving": "1 puri (30g)", "serving_g": 30},
    {"name": "Bhatura", "cal": 330, "pro": 6.5, "fat": 15.0, "carb": 42.0, "fiber": 1.5, "serving": "1 bhatura (60g)", "serving_g": 60},

    # --- Dals & Pulses ---
    {"name": "Dal, toor (arhar), cooked", "cal": 118, "pro": 7.6, "fat": 0.6, "carb": 21.0, "fiber": 3.2, "serving": "1 bowl (200ml)", "serving_g": 200},
    {"name": "Dal, moong, cooked", "cal": 105, "pro": 7.0, "fat": 0.4, "carb": 18.3, "fiber": 2.0, "serving": "1 bowl (200ml)", "serving_g": 200},
    {"name": "Dal, masoor, cooked", "cal": 116, "pro": 9.0, "fat": 0.4, "carb": 20.2, "fiber": 1.9, "serving": "1 bowl (200ml)", "serving_g": 200},
    {"name": "Dal, chana, cooked", "cal": 130, "pro": 8.9, "fat": 2.7, "carb": 21.0, "fiber": 5.0, "serving": "1 bowl (200ml)", "serving_g": 200},
    {"name": "Dal, urad, cooked", "cal": 120, "pro": 7.8, "fat": 0.6, "carb": 21.0, "fiber": 3.0, "serving": "1 bowl (200ml)", "serving_g": 200},
    {"name": "Rajma (kidney beans), cooked", "cal": 127, "pro": 8.7, "fat": 0.5, "carb": 22.8, "fiber": 6.4, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Chole / Chana masala", "cal": 160, "pro": 8.9, "fat": 5.5, "carb": 22.0, "fiber": 6.0, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Sambar", "cal": 65, "pro": 3.0, "fat": 2.0, "carb": 9.0, "fiber": 2.0, "serving": "1 bowl (200ml)", "serving_g": 200},
    {"name": "Rasam", "cal": 30, "pro": 1.0, "fat": 0.5, "carb": 5.5, "fiber": 0.5, "serving": "1 bowl (200ml)", "serving_g": 200},

    # --- Vegetables (cooked sabzi) ---
    {"name": "Aloo gobi (potato cauliflower)", "cal": 90, "pro": 2.5, "fat": 3.5, "carb": 13.0, "fiber": 2.5, "serving": "1 bowl (150g)", "serving_g": 150},
    {"name": "Palak paneer", "cal": 170, "pro": 10.0, "fat": 12.0, "carb": 6.0, "fiber": 2.5, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Paneer butter masala", "cal": 220, "pro": 11.0, "fat": 16.0, "carb": 8.0, "fiber": 1.5, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Matar paneer", "cal": 180, "pro": 10.0, "fat": 12.0, "carb": 10.0, "fiber": 3.0, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Bhindi masala (okra)", "cal": 80, "pro": 2.0, "fat": 4.0, "carb": 9.0, "fiber": 3.5, "serving": "1 bowl (150g)", "serving_g": 150},
    {"name": "Baingan bharta (eggplant)", "cal": 85, "pro": 2.0, "fat": 4.5, "carb": 10.0, "fiber": 3.0, "serving": "1 bowl (150g)", "serving_g": 150},
    {"name": "Aloo matar (potato peas)", "cal": 110, "pro": 3.0, "fat": 4.0, "carb": 16.0, "fiber": 3.0, "serving": "1 bowl (150g)", "serving_g": 150},
    {"name": "Mixed vegetable curry", "cal": 85, "pro": 2.5, "fat": 3.5, "carb": 12.0, "fiber": 3.0, "serving": "1 bowl (150g)", "serving_g": 150},
    {"name": "Lauki (bottle gourd) sabzi", "cal": 45, "pro": 1.5, "fat": 2.0, "carb": 6.0, "fiber": 1.5, "serving": "1 bowl (150g)", "serving_g": 150},
    {"name": "Tinda sabzi", "cal": 50, "pro": 1.5, "fat": 2.5, "carb": 6.5, "fiber": 1.5, "serving": "1 bowl (150g)", "serving_g": 150},
    {"name": "Kadhi (yogurt curry)", "cal": 100, "pro": 3.5, "fat": 5.0, "carb": 10.0, "fiber": 0.5, "serving": "1 bowl (200ml)", "serving_g": 200},

    # --- Non-Veg ---
    {"name": "Chicken curry", "cal": 150, "pro": 15.0, "fat": 8.0, "carb": 5.0, "fiber": 1.0, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Chicken biryani", "cal": 200, "pro": 10.0, "fat": 8.0, "carb": 22.0, "fiber": 1.0, "serving": "1 plate (250g)", "serving_g": 250},
    {"name": "Butter chicken", "cal": 195, "pro": 14.0, "fat": 12.0, "carb": 8.0, "fiber": 1.0, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Chicken tikka", "cal": 175, "pro": 22.0, "fat": 8.0, "carb": 3.0, "fiber": 0.5, "serving": "4 pieces (120g)", "serving_g": 120},
    {"name": "Tandoori chicken", "cal": 165, "pro": 25.0, "fat": 6.0, "carb": 3.0, "fiber": 0.5, "serving": "1 leg piece (150g)", "serving_g": 150},
    {"name": "Mutton curry", "cal": 190, "pro": 16.0, "fat": 12.0, "carb": 5.0, "fiber": 1.0, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Fish curry", "cal": 120, "pro": 14.0, "fat": 5.0, "carb": 5.0, "fiber": 0.5, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Egg curry", "cal": 140, "pro": 10.0, "fat": 9.0, "carb": 5.0, "fiber": 1.0, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Egg, boiled", "cal": 155, "pro": 13.0, "fat": 11.0, "carb": 1.1, "fiber": 0, "serving": "1 egg (50g)", "serving_g": 50},
    {"name": "Egg bhurji (scrambled)", "cal": 180, "pro": 12.0, "fat": 13.0, "carb": 3.0, "fiber": 0.5, "serving": "2 eggs (120g)", "serving_g": 120},
    {"name": "Keema (minced meat)", "cal": 200, "pro": 17.0, "fat": 13.0, "carb": 4.0, "fiber": 1.0, "serving": "1 bowl (200g)", "serving_g": 200},

    # --- Rice dishes ---
    {"name": "Veg biryani", "cal": 150, "pro": 3.5, "fat": 5.0, "carb": 24.0, "fiber": 1.5, "serving": "1 plate (250g)", "serving_g": 250},
    {"name": "Veg pulao", "cal": 140, "pro": 3.0, "fat": 4.0, "carb": 23.0, "fiber": 1.5, "serving": "1 plate (250g)", "serving_g": 250},
    {"name": "Jeera rice", "cal": 145, "pro": 3.0, "fat": 3.0, "carb": 27.0, "fiber": 0.5, "serving": "1 plate (200g)", "serving_g": 200},
    {"name": "Lemon rice", "cal": 155, "pro": 3.0, "fat": 4.0, "carb": 27.0, "fiber": 0.5, "serving": "1 plate (200g)", "serving_g": 200},
    {"name": "Curd rice / Dahi chawal", "cal": 120, "pro": 4.0, "fat": 3.0, "carb": 20.0, "fiber": 0.3, "serving": "1 bowl (200g)", "serving_g": 200},
    {"name": "Khichdi", "cal": 115, "pro": 4.5, "fat": 2.0, "carb": 20.0, "fiber": 2.0, "serving": "1 bowl (200g)", "serving_g": 200},

    # --- Snacks ---
    {"name": "Samosa, vegetable", "cal": 260, "pro": 4.5, "fat": 14.0, "carb": 30.0, "fiber": 2.0, "serving": "1 samosa (80g)", "serving_g": 80},
    {"name": "Pakora / Bhajiya", "cal": 280, "pro": 5.0, "fat": 18.0, "carb": 25.0, "fiber": 2.0, "serving": "5 pieces (100g)", "serving_g": 100},
    {"name": "Vada pav", "cal": 290, "pro": 5.0, "fat": 13.0, "carb": 38.0, "fiber": 2.0, "serving": "1 piece (150g)", "serving_g": 150},
    {"name": "Pav bhaji", "cal": 180, "pro": 4.0, "fat": 8.0, "carb": 24.0, "fiber": 3.0, "serving": "1 plate (250g)", "serving_g": 250},
    {"name": "Dhokla", "cal": 160, "pro": 6.0, "fat": 3.0, "carb": 28.0, "fiber": 2.0, "serving": "3 pieces (100g)", "serving_g": 100},
    {"name": "Kachori", "cal": 320, "pro": 6.0, "fat": 18.0, "carb": 34.0, "fiber": 3.0, "serving": "1 kachori (60g)", "serving_g": 60},
    {"name": "Aloo tikki", "cal": 200, "pro": 3.0, "fat": 10.0, "carb": 25.0, "fiber": 2.0, "serving": "1 tikki (80g)", "serving_g": 80},
    {"name": "Pani puri / Golgappa", "cal": 35, "pro": 0.5, "fat": 0.5, "carb": 7.0, "fiber": 0.3, "serving": "1 piece (20g)", "serving_g": 20},

    # --- Dairy ---
    {"name": "Paneer (cottage cheese)", "cal": 265, "pro": 18.3, "fat": 20.8, "carb": 1.2, "fiber": 0, "serving": "100g", "serving_g": 100},
    {"name": "Curd / Dahi (plain yogurt)", "cal": 60, "pro": 3.1, "fat": 3.3, "carb": 4.7, "fiber": 0, "serving": "1 bowl (100g)", "serving_g": 100},
    {"name": "Lassi, sweet", "cal": 75, "pro": 2.5, "fat": 2.0, "carb": 12.0, "fiber": 0, "serving": "1 glass (200ml)", "serving_g": 200},
    {"name": "Lassi, salted", "cal": 40, "pro": 2.5, "fat": 2.0, "carb": 3.0, "fiber": 0, "serving": "1 glass (200ml)", "serving_g": 200},
    {"name": "Chaas / Buttermilk", "cal": 25, "pro": 1.5, "fat": 0.5, "carb": 3.5, "fiber": 0, "serving": "1 glass (200ml)", "serving_g": 200},
    {"name": "Raita", "cal": 50, "pro": 2.5, "fat": 2.0, "carb": 5.0, "fiber": 0.5, "serving": "1 bowl (100g)", "serving_g": 100},
    {"name": "Ghee", "cal": 900, "pro": 0, "fat": 99.5, "carb": 0, "fiber": 0, "serving": "1 tsp (5g)", "serving_g": 5},
    {"name": "Milk, whole (cow)", "cal": 62, "pro": 3.2, "fat": 3.3, "carb": 4.8, "fiber": 0, "serving": "1 glass (200ml)", "serving_g": 200},
    {"name": "Milk, toned", "cal": 50, "pro": 3.0, "fat": 1.5, "carb": 5.0, "fiber": 0, "serving": "1 glass (200ml)", "serving_g": 200},

    # --- Sweets & Desserts ---
    {"name": "Gulab jamun", "cal": 380, "pro": 5.0, "fat": 15.0, "carb": 57.0, "fiber": 0.5, "serving": "1 piece (40g)", "serving_g": 40},
    {"name": "Jalebi", "cal": 380, "pro": 2.0, "fat": 10.0, "carb": 70.0, "fiber": 0.5, "serving": "1 piece (30g)", "serving_g": 30},
    {"name": "Rasgulla", "cal": 185, "pro": 5.0, "fat": 1.0, "carb": 40.0, "fiber": 0, "serving": "1 piece (50g)", "serving_g": 50},
    {"name": "Kheer (rice pudding)", "cal": 150, "pro": 4.0, "fat": 5.0, "carb": 23.0, "fiber": 0.3, "serving": "1 bowl (150g)", "serving_g": 150},
    {"name": "Halwa, sooji", "cal": 340, "pro": 4.0, "fat": 15.0, "carb": 48.0, "fiber": 1.0, "serving": "1 bowl (100g)", "serving_g": 100},
    {"name": "Ladoo, besan", "cal": 420, "pro": 8.0, "fat": 22.0, "carb": 50.0, "fiber": 2.0, "serving": "1 ladoo (40g)", "serving_g": 40},
    {"name": "Barfi, kaju", "cal": 400, "pro": 7.0, "fat": 18.0, "carb": 55.0, "fiber": 1.0, "serving": "1 piece (30g)", "serving_g": 30},

    # --- Chutneys & Accompaniments ---
    {"name": "Coconut chutney", "cal": 120, "pro": 2.0, "fat": 9.0, "carb": 8.0, "fiber": 2.0, "serving": "2 tbsp (30g)", "serving_g": 30},
    {"name": "Mint chutney (pudina)", "cal": 20, "pro": 1.0, "fat": 0.2, "carb": 4.0, "fiber": 1.5, "serving": "2 tbsp (30g)", "serving_g": 30},
    {"name": "Mango pickle (achar)", "cal": 175, "pro": 1.0, "fat": 14.0, "carb": 12.0, "fiber": 2.0, "serving": "1 tbsp (15g)", "serving_g": 15},
    {"name": "Papad, roasted", "cal": 310, "pro": 18.0, "fat": 5.0, "carb": 48.0, "fiber": 5.0, "serving": "1 papad (15g)", "serving_g": 15},
    {"name": "Papad, fried", "cal": 420, "pro": 16.0, "fat": 18.0, "carb": 48.0, "fiber": 5.0, "serving": "1 papad (15g)", "serving_g": 15},

    # --- Beverages ---
    {"name": "Chai (tea with milk & sugar)", "cal": 40, "pro": 1.0, "fat": 1.0, "carb": 7.0, "fiber": 0, "serving": "1 cup (150ml)", "serving_g": 150},
    {"name": "Coffee, filter (with milk & sugar)", "cal": 45, "pro": 1.2, "fat": 1.5, "carb": 7.0, "fiber": 0, "serving": "1 cup (150ml)", "serving_g": 150},
    {"name": "Nimbu pani (lemon water, sweet)", "cal": 45, "pro": 0.2, "fat": 0, "carb": 11.0, "fiber": 0, "serving": "1 glass (250ml)", "serving_g": 250},
    {"name": "Mango lassi", "cal": 130, "pro": 3.0, "fat": 3.0, "carb": 23.0, "fiber": 0.5, "serving": "1 glass (200ml)", "serving_g": 200},
    {"name": "Coconut water", "cal": 19, "pro": 0.7, "fat": 0.2, "carb": 3.7, "fiber": 1.1, "serving": "1 glass (240ml)", "serving_g": 240},
    {"name": "Sugarcane juice", "cal": 73, "pro": 0.2, "fat": 0, "carb": 18.2, "fiber": 0, "serving": "1 glass (250ml)", "serving_g": 250},

    # --- Fruits (raw) ---
    {"name": "Banana", "cal": 89, "pro": 1.1, "fat": 0.3, "carb": 22.8, "fiber": 2.6, "serving": "1 medium (118g)", "serving_g": 118},
    {"name": "Mango", "cal": 60, "pro": 0.8, "fat": 0.4, "carb": 15.0, "fiber": 1.6, "serving": "1 cup (165g)", "serving_g": 165},
    {"name": "Apple", "cal": 52, "pro": 0.3, "fat": 0.2, "carb": 13.8, "fiber": 2.4, "serving": "1 medium (182g)", "serving_g": 182},
    {"name": "Papaya", "cal": 43, "pro": 0.5, "fat": 0.3, "carb": 10.8, "fiber": 1.7, "serving": "1 cup (140g)", "serving_g": 140},
    {"name": "Guava", "cal": 68, "pro": 2.6, "fat": 1.0, "carb": 14.3, "fiber": 5.4, "serving": "1 medium (100g)", "serving_g": 100},
    {"name": "Chikoo (sapodilla)", "cal": 83, "pro": 0.4, "fat": 1.1, "carb": 20.0, "fiber": 5.3, "serving": "1 medium (100g)", "serving_g": 100},
    {"name": "Pomegranate", "cal": 83, "pro": 1.7, "fat": 1.2, "carb": 18.7, "fiber": 4.0, "serving": "1 cup seeds (174g)", "serving_g": 174},
    {"name": "Watermelon", "cal": 30, "pro": 0.6, "fat": 0.2, "carb": 7.6, "fiber": 0.4, "serving": "1 cup (152g)", "serving_g": 152},

    # --- Common additions ---
    {"name": "Dal tadka", "cal": 130, "pro": 7.0, "fat": 3.0, "carb": 19.0, "fiber": 3.0, "serving": "1 bowl (200ml)", "serving_g": 200},
    {"name": "Dal fry", "cal": 140, "pro": 7.5, "fat": 4.0, "carb": 19.0, "fiber": 3.0, "serving": "1 bowl (200ml)", "serving_g": 200},
    {"name": "Rajma chawal (with rice)", "cal": 150, "pro": 6.0, "fat": 2.0, "carb": 28.0, "fiber": 4.0, "serving": "1 plate (300g)", "serving_g": 300},
    {"name": "Chole bhature (1 plate)", "cal": 450, "pro": 12.0, "fat": 20.0, "carb": 58.0, "fiber": 6.0, "serving": "1 plate (250g)", "serving_g": 250},
    {"name": "Thali, veg (average)", "cal": 700, "pro": 18.0, "fat": 22.0, "carb": 110.0, "fiber": 10.0, "serving": "1 thali", "serving_g": 500},
    {"name": "Maggi noodles, cooked", "cal": 205, "pro": 4.5, "fat": 8.5, "carb": 28.5, "fiber": 1.0, "serving": "1 pack (70g dry)", "serving_g": 200},
    {"name": "Bread, white (sandwich)", "cal": 265, "pro": 9.0, "fat": 3.2, "carb": 49.0, "fiber": 2.7, "serving": "1 slice (25g)", "serving_g": 25},
    {"name": "Oats, cooked (porridge)", "cal": 71, "pro": 2.5, "fat": 1.5, "carb": 12.0, "fiber": 1.7, "serving": "1 bowl (200g)", "serving_g": 200},
]
# fmt: on


def seed():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()

    added = 0
    skipped = 0

    for food in INDIAN_FOODS:
        existing = db.query(FoodItem).filter(
            FoodItem.name == food["name"],
            FoodItem.source == "custom",
            FoodItem.is_indian == True,
        ).first()

        if existing:
            skipped += 1
            continue

        item = FoodItem(
            source="custom",
            name=food["name"],
            calories_per_100g=food["cal"],
            protein_per_100g=food["pro"],
            fat_per_100g=food["fat"],
            carbs_per_100g=food["carb"],
            fiber_per_100g=food.get("fiber", 0),
            sodium_per_100g=0,
            serving_size_g=food["serving_g"],
            serving_description=food["serving"],
            is_indian=True,
            verified=True,
        )
        db.add(item)
        added += 1

    db.commit()
    db.close()
    print(f"Seeded {added} Indian foods ({skipped} already existed)")


if __name__ == "__main__":
    seed()
