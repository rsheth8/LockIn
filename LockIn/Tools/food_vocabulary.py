# Global food vocabulary for MobileCLIP zero-shot matching.
#
# These are dish names as they'd plausibly appear in a web image caption —
# that's what CLIP was trained on, so common English names for dishes beat
# formal/native-script names for recognition purposes.
#
# Depth is deliberately uneven: South Asian and vegetarian coverage is densest
# (the app's primary user), with broad coverage everywhere else so the
# classifier isn't blind to any cuisine.

SOUTH_ASIAN = [
    "chicken biryani", "vegetable biryani", "mutton biryani", "hyderabadi biryani",
    "chicken tikka masala", "butter chicken", "chicken curry", "goat curry",
    "palak paneer", "paneer butter masala", "paneer tikka", "shahi paneer",
    "matar paneer", "kadai paneer", "chilli paneer", "paneer bhurji",
    "chana masala", "chole bhature", "rajma", "dal makhani", "dal tadka",
    "moong dal", "toor dal", "chana dal", "sambar", "rasam", "dal fry",
    "aloo gobi", "baingan bharta", "bhindi masala", "aloo matar", "malai kofta",
    "navratan korma", "vegetable korma", "mixed vegetable curry", "avial",
    "masala dosa", "plain dosa", "rava dosa", "onion uttapam", "idli sambar",
    "medu vada", "upma", "poha", "pongal", "appam", "puttu", "dhokla",
    "roti", "chapati", "naan", "garlic naan", "butter naan", "paratha",
    "aloo paratha", "gobi paratha", "paneer paratha", "puri", "bhatura",
    "kulcha", "thepla", "roomali roti", "tandoori roti",
    "plain basmati rice", "jeera rice", "lemon rice", "curd rice", "pulao",
    "vegetable pulao", "khichdi", "biryani rice",
    "samosa", "pakora", "onion bhaji", "vada pav", "pav bhaji", "misal pav",
    "pani puri", "bhel puri", "sev puri", "dahi puri", "aloo tikki",
    "kathi roll", "frankie roll", "dabeli",
    "tandoori chicken", "chicken tikka", "seekh kebab", "shami kebab",
    "chicken 65", "fish curry", "prawn curry", "egg curry", "keema",
    "raita", "boondi raita", "papad", "pickle achar", "chutney",
    "gulab jamun", "rasgulla", "jalebi", "kheer", "halwa", "gajar ka halwa",
    "barfi", "laddu", "besan ladoo", "rasmalai", "kulfi", "shrikhand",
    "mango lassi", "sweet lassi", "salted lassi", "masala chai", "filter coffee",
    "thali platter", "south indian thali", "gujarati thali",
    "hyderabadi haleem", "nihari", "korma", "vindaloo", "rogan josh",
    "dhal curry", "kottu roti", "hoppers", "string hoppers",
    "momo dumplings", "thukpa", "dal bhat", "biryani with raita",
]

EAST_ASIAN = [
    "sushi rolls", "nigiri sushi", "sashimi", "california roll", "spicy tuna roll",
    "ramen noodle soup", "tonkotsu ramen", "shoyu ramen", "miso ramen",
    "udon noodle soup", "soba noodles", "yakisoba", "tempura", "katsu curry",
    "chicken katsu", "tonkatsu", "gyoza dumplings", "onigiri rice ball",
    "miso soup", "chirashi bowl", "okonomiyaki", "takoyaki", "donburi rice bowl",
    "teriyaki chicken", "unagi eel rice", "shabu shabu", "japanese curry rice",
    "kimchi", "bibimbap", "korean fried chicken", "bulgogi", "galbi short ribs",
    "tteokbokki", "japchae", "kimchi jjigae", "sundubu jjigae", "korean bbq",
    "samgyeopsal", "kimbap", "haemul pajeon", "korean corn dog",
    "fried rice", "egg fried rice", "yangzhou fried rice", "chow mein",
    "lo mein", "dan dan noodles", "beef noodle soup", "wonton soup",
    "hot and sour soup", "egg drop soup", "dumplings", "soup dumplings",
    "xiao long bao", "har gow", "siu mai", "char siu bao", "dim sum platter",
    "peking duck", "kung pao chicken", "general tso chicken", "orange chicken",
    "sweet and sour pork", "mapo tofu", "twice cooked pork", "hot pot",
    "chow fun", "spring rolls", "egg rolls", "scallion pancake", "congee",
    "century egg congee", "salt and pepper squid", "beef and broccoli",
    "char siu pork", "roast duck rice", "claypot rice", "mooncake",
    "taiwanese beef noodle", "bubble tea", "boba milk tea", "egg tart",
]

SOUTHEAST_ASIAN = [
    "pad thai", "pad see ew", "drunken noodles", "green curry", "red curry",
    "massaman curry", "panang curry", "tom yum soup", "tom kha gai",
    "thai fried rice", "pineapple fried rice", "som tam papaya salad",
    "mango sticky rice", "satay skewers", "larb", "khao soi", "thai basil chicken",
    "pho noodle soup", "banh mi sandwich", "vietnamese spring rolls",
    "fresh summer rolls", "bun cha", "bun bo hue", "com tam broken rice",
    "vietnamese coffee", "banh xeo",
    "nasi goreng", "mie goreng", "rendang", "satay ayam", "gado gado",
    "nasi lemak", "laksa", "char kway teow", "hainanese chicken rice",
    "roti canai", "bak kut teh", "chili crab", "beef rendang", "sambal",
    "adobo", "sinigang", "lechon", "pancit", "lumpia", "kare kare",
    "halo halo", "sisig", "amok curry", "lok lak", "khao pad",
    # Descriptive aliases for dishes the first evaluation missed: som tam came
    # back as "taiwanese beef noodle" (shredded papaya reads as noodles) and
    # adobo as "ham".
    "green papaya salad", "filipino adobo", "braised pork in soy sauce",
    "thai papaya salad with peanuts",
]

MIDDLE_EASTERN_AND_AFRICAN = [
    "hummus", "baba ganoush", "falafel", "shawarma wrap", "chicken shawarma",
    "beef shawarma", "kebab platter", "shish kebab", "kofta kebab", "doner kebab",
    "tabbouleh", "fattoush salad", "mujadara", "shakshuka", "manakish",
    "stuffed grape leaves", "dolma", "labneh", "pita bread", "lavash",
    "mansaf", "maqluba", "kabsa", "machboos", "fatteh", "sambusak",
    "baklava", "kunafa", "halva", "turkish delight", "basbousa",
    "turkish breakfast", "lahmacun", "pide", "iskender kebab", "menemen",
    "persian kebab koobideh", "ghormeh sabzi", "fesenjan", "tahchin",
    "saffron rice", "adas polo", "ash reshteh",
    "couscous", "tagine", "lamb tagine", "harira soup", "msemen", "bastilla",
    "injera with wot", "doro wat", "shiro", "misir wot", "tibs",
    "jollof rice", "egusi soup", "fufu", "suya skewers", "moin moin",
    "bunny chow", "bobotie", "chakalaka", "koshari", "ful medames",
    # African coverage is where zero-shot CLIP is measurably weakest — a first
    # pass scored 40% top-1 here against 83% overall, missing fufu as
    # "rasgulla" and egusi soup as "sunflower seeds". These add both more
    # dishes and *descriptive* phrasings of the ones it fumbled, since CLIP
    # was trained on web captions and often knows "ethiopian chicken stew"
    # where it doesn't know "doro wat".
    "ethiopian chicken stew", "ethiopian food platter", "ethiopian lentil stew",
    "melon seed soup", "nigerian soup with fufu", "pounded yam", "eba",
    "amala", "banku", "ugali", "waakye", "west african jollof rice",
    "nigerian party rice", "okra soup", "ogbono soup", "pepper soup",
    "akara", "puff puff", "kelewele", "nyama choma", "grilled goat meat",
    "yassa chicken", "thieboudienne", "maafe peanut stew", "biltong",
    "boerewors", "pap and stew", "samp and beans", "harissa paste",
    "zaalouk", "shakshuka with bread", "koshari egyptian",
    "south african curry bake", "cape malay curry",
]

EUROPEAN = [
    "margherita pizza", "pepperoni pizza", "neapolitan pizza", "calzone",
    "spaghetti bolognese", "spaghetti carbonara", "cacio e pepe", "penne arrabbiata",
    "fettuccine alfredo", "lasagna", "ravioli", "gnocchi", "pesto pasta",
    "risotto", "mushroom risotto", "osso buco", "chicken parmesan", "bruschetta",
    "caprese salad", "minestrone soup", "tiramisu", "panna cotta", "cannoli",
    "focaccia", "arancini", "prosciutto and melon",
    "paella", "seafood paella", "tapas platter", "patatas bravas", "gazpacho",
    "tortilla espanola", "jamon iberico", "churros", "croquetas",
    "croissant", "pain au chocolat", "baguette sandwich", "quiche lorraine",
    "french onion soup", "coq au vin", "beef bourguignon", "ratatouille",
    "cassoulet", "crepes", "creme brulee", "macarons", "escargot",
    "steak frites", "nicoise salad", "duck confit",
    "fish and chips", "shepherds pie", "cottage pie", "bangers and mash",
    "full english breakfast", "sunday roast", "yorkshire pudding",
    "cornish pasty", "scotch egg", "beef wellington", "scones with cream",
    "sticky toffee pudding", "ploughmans lunch",
    "schnitzel", "wiener schnitzel", "bratwurst", "sauerkraut", "pretzel",
    "spaetzle", "goulash", "sauerbraten", "black forest cake", "strudel",
    "pierogi", "borscht", "beef stroganoff", "blini", "kielbasa", "golabki",
    "moussaka", "greek salad", "souvlaki", "gyro", "spanakopita", "tzatziki",
    "dolmades", "avgolemono soup", "loukoumades",
    "smorgasbord", "swedish meatballs", "gravlax", "herring", "rye bread",
    "smorrebrod", "waffles", "dutch pancakes", "stroopwafel", "fondue", "raclette",
]

AMERICAS = [
    "cheeseburger", "hamburger", "bacon cheeseburger", "smash burger",
    "hot dog", "chili dog", "french fries", "loaded fries", "onion rings",
    "buffalo wings", "chicken wings", "fried chicken", "chicken tenders",
    "mac and cheese", "bbq ribs", "pulled pork sandwich", "brisket plate",
    "cornbread", "biscuits and gravy", "clam chowder", "lobster roll",
    "philly cheesesteak", "reuben sandwich", "club sandwich", "blt sandwich",
    "grilled cheese sandwich", "tuna melt", "meatloaf", "pot roast",
    "pancakes with syrup", "waffles with berries", "french toast",
    "eggs benedict", "scrambled eggs", "omelette", "breakfast burrito",
    "bagel with cream cheese", "avocado toast", "oatmeal bowl", "granola bowl",
    "caesar salad", "cobb salad", "garden salad", "coleslaw", "potato salad",
    "apple pie", "pumpkin pie", "cheesecake", "brownies", "chocolate chip cookies",
    "donuts", "cupcakes", "banana bread", "ice cream sundae", "milkshake",
    "tacos", "carne asada tacos", "al pastor tacos", "fish tacos", "burrito",
    "burrito bowl", "quesadilla", "enchiladas", "chilaquiles", "tamales",
    "pozole", "menudo", "mole poblano", "elote corn", "nachos", "guacamole",
    "salsa and chips", "fajitas", "huevos rancheros", "torta sandwich",
    "empanadas", "arepas", "feijoada", "churrasco", "asado", "chimichurri steak",
    "ceviche", "lomo saltado", "aji de gallina", "anticuchos", "pupusas",
    "ropa vieja", "cuban sandwich", "tostones", "mofongo", "jerk chicken",
    "rice and peas", "curry goat", "roti wrap", "callaloo", "acai bowl",
    "pao de queijo", "dulce de leche", "flan", "tres leches cake", "alfajores",
]

STAPLES_AND_INGREDIENTS = [
    "grilled chicken breast", "roasted chicken", "steak", "grilled steak",
    "salmon fillet", "grilled salmon", "baked fish", "shrimp", "grilled shrimp",
    "pork chop", "lamb chops", "turkey breast", "ground beef", "meatballs",
    "bacon", "sausages", "ham", "canned tuna",
    "boiled eggs", "fried egg", "poached eggs", "egg whites",
    "tofu", "grilled tofu", "tempeh", "seitan", "edamame",
    "black beans", "kidney beans", "chickpeas", "lentils", "green peas",
    "white rice", "brown rice", "quinoa", "couscous grain", "bulgur",
    "pasta", "whole wheat bread", "white bread", "sourdough bread", "tortilla",
    "sweet potato", "baked potato", "mashed potatoes", "roasted potatoes",
    "broccoli", "cauliflower", "spinach", "kale", "green beans", "asparagus",
    "brussels sprouts", "carrots", "bell peppers", "zucchini", "eggplant",
    "mushrooms", "tomatoes", "cucumber", "lettuce", "cabbage", "corn on the cob",
    "mixed vegetables", "stir fried vegetables", "roasted vegetables", "side salad",
    "apple", "banana", "orange", "grapes", "strawberries", "blueberries",
    "mango", "pineapple", "watermelon", "papaya", "pear", "peach", "kiwi",
    "pomegranate", "avocado", "mixed berries", "fruit salad", "dates",
    "greek yogurt", "plain yogurt", "cottage cheese", "milk", "cheese slices",
    "mozzarella", "cheddar cheese", "feta cheese", "butter", "cream cheese",
    "almonds", "walnuts", "cashews", "peanuts", "pistachios", "mixed nuts",
    "peanut butter", "almond butter", "chia seeds", "flax seeds", "sunflower seeds",
    "protein shake", "protein bar", "protein powder scoop", "meal replacement shake",
    "smoothie", "green smoothie", "orange juice", "coffee", "black coffee",
    "latte", "cappuccino", "espresso", "green tea", "iced tea", "soda",
    "energy drink", "coconut water", "beer", "wine", "cocktail",
    "granola", "muesli", "breakfast cereal", "cereal with milk", "porridge",
    "rice cakes", "crackers", "popcorn", "potato chips", "trail mix",
    "chocolate bar", "dark chocolate", "candy", "gummy bears",
    "soup", "vegetable soup", "chicken soup", "lentil soup", "tomato soup",
    "sandwich", "wrap", "grain bowl", "poke bowl", "buddha bowl", "salad bowl",
    "charcuterie board", "leftovers plate", "home cooked meal", "restaurant plate",
]

# Non-food classes. Without these every photo gets forced into a food label —
# a photo of a person or a receipt would confidently come back as "soup".
# Their presence lets the classifier abstain when nothing food-like is in frame.
NON_FOOD = [
    "a person", "a selfie of a person", "a pet dog", "a cat", "a car",
    "a building", "a landscape", "a computer screen", "a phone screen",
    "a document or receipt", "a book", "furniture in a room", "clothing",
    "an empty plate", "an empty table", "a blurry photo of nothing",
    "a kitchen counter", "a grocery store shelf", "a restaurant menu",
]

FOOD_NAMES = (
    SOUTH_ASIAN
    + EAST_ASIAN
    + SOUTHEAST_ASIAN
    + MIDDLE_EASTERN_AND_AFRICAN
    + EUROPEAN
    + AMERICAS
    + STAPLES_AND_INGREDIENTS
)

if __name__ == "__main__":
    seen = set()
    dupes = [n for n in FOOD_NAMES if n in seen or seen.add(n)]
    print(f"food: {len(FOOD_NAMES)} ({len(set(FOOD_NAMES))} unique)")
    print(f"non-food: {len(NON_FOOD)}")
    if dupes:
        print("DUPLICATES:", dupes)
