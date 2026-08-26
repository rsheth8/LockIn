# Stress-test set: Wikipedia article -> vocabulary labels we'd accept.
#
# Deliberately weighted toward cuisines a Western-trained model is most likely
# to fumble (South Asian, African, Southeast Asian), and includes several
# visually-confusable pairs (dosa/uttapam, ramen/pho, tacos/burritos) so the
# score isn't inflated by easy cases.

STRESS = {
    # --- South Asian ---
    "Palak paneer": {"palak paneer", "matar paneer", "kadai paneer", "shahi paneer", "paneer butter masala", "navratan korma", "vegetable korma"},
    "Masala dosa": {"masala dosa", "plain dosa", "rava dosa", "onion uttapam"},
    "Idli": {"idli sambar", "medu vada", "dhokla", "appam", "puttu"},
    "Biryani": {"chicken biryani", "vegetable biryani", "mutton biryani", "hyderabadi biryani", "biryani rice", "biryani with raita", "pulao", "vegetable pulao"},
    "Butter chicken": {"butter chicken", "chicken tikka masala", "chicken curry", "korma", "rogan josh", "paneer butter masala"},
    "Chole bhature": {"chole bhature", "chana masala", "bhatura", "puri", "samosa"},
    "Samosa": {"samosa", "pakora", "sambusak", "onion bhaji", "dabeli"},
    "Pani puri": {"pani puri", "bhel puri", "sev puri", "dahi puri"},
    "Vada pav": {"vada pav", "pav bhaji", "misal pav", "dabeli", "aloo tikki"},
    "Dal makhani": {"dal makhani", "dal tadka", "rajma", "dal fry", "moong dal", "toor dal", "chana dal", "dhal curry"},
    "Tandoori chicken": {"tandoori chicken", "chicken tikka", "seekh kebab", "chicken 65", "shami kebab"},
    "Naan": {"naan", "garlic naan", "butter naan", "roti", "chapati", "kulcha", "tandoori roti", "paratha"},
    "Gulab jamun": {"gulab jamun", "rasgulla", "laddu", "besan ladoo", "barfi", "rasmalai"},
    "Jalebi": {"jalebi", "gulab jamun", "laddu", "loukoumades"},
    "Momo (food)": {"momo dumplings", "dumplings", "gyoza dumplings", "soup dumplings", "siu mai"},

    # --- East Asian ---
    "Sushi": {"sushi rolls", "nigiri sushi", "sashimi", "california roll", "spicy tuna roll", "chirashi bowl", "kimbap"},
    "Ramen": {"ramen noodle soup", "tonkotsu ramen", "shoyu ramen", "miso ramen", "udon noodle soup", "beef noodle soup", "taiwanese beef noodle"},
    "Tempura": {"tempura", "karaage", "tonkatsu", "chicken katsu", "fried chicken"},
    "Okonomiyaki": {"okonomiyaki", "takoyaki", "japanese curry rice", "scallion pancake", "haemul pajeon"},
    "Bibimbap": {"bibimbap", "japchae", "donburi rice bowl", "poke bowl", "grain bowl", "buddha bowl"},
    "Kimchi": {"kimchi", "kimchi jjigae", "sauerkraut", "tteokbokki"},
    "Tteokbokki": {"tteokbokki", "kimchi jjigae", "korean fried chicken", "mapo tofu"},
    "Bulgogi": {"bulgogi", "galbi short ribs", "korean bbq", "samgyeopsal", "japchae"},
    "Peking duck": {"peking duck", "roast duck rice", "char siu pork", "char siu bao"},
    "Mapo doufu": {"mapo tofu", "kung pao chicken", "twice cooked pork", "dan dan noodles"},
    "Dim sum": {"dim sum platter", "siu mai", "har gow", "soup dumplings", "xiao long bao", "dumplings", "char siu bao"},
    "Fried rice": {"fried rice", "egg fried rice", "yangzhou fried rice", "thai fried rice", "khao pad", "nasi goreng"},
    "Hot pot": {"hot pot", "shabu shabu", "sundubu jjigae", "kimchi jjigae"},

    # --- Southeast Asian ---
    "Pad thai": {"pad thai", "pad see ew", "drunken noodles", "char kway teow", "khao soi", "mie goreng", "yakisoba"},
    "Green curry": {"green curry", "red curry", "panang curry", "massaman curry", "khao soi", "laksa"},
    "Tom yum": {"tom yum soup", "tom kha gai", "laksa", "bun bo hue"},
    "Som tam": {"som tam papaya salad", "larb", "gado gado", "side salad", "green papaya salad", "thai papaya salad with peanuts"},
    "Mango sticky rice": {"mango sticky rice", "kheer", "halo halo", "coconut water"},
    "Pho": {"pho noodle soup", "bun bo hue", "beef noodle soup", "ramen noodle soup", "udon noodle soup"},
    "Bánh mì": {"banh mi sandwich", "sandwich", "wrap", "torta sandwich", "club sandwich"},
    "Gỏi cuốn": {"vietnamese spring rolls", "fresh summer rolls", "spring rolls", "lumpia"},
    "Nasi lemak": {"nasi lemak", "nasi goreng", "fried rice", "sambal"},
    "Rendang": {"rendang", "beef rendang", "goat curry", "massaman curry", "keema"},
    "Laksa": {"laksa", "khao soi", "tom yum soup", "curry goat", "pho noodle soup"},
    "Adobo": {"adobo", "sinigang", "kare kare", "pork chop", "chicken curry", "filipino adobo", "braised pork in soy sauce"},
    "Hainanese chicken rice": {"hainanese chicken rice", "roast duck rice", "claypot rice", "com tam broken rice"},

    # --- Middle Eastern / Persian / Turkish ---
    "Hummus": {"hummus", "baba ganoush", "labneh", "guacamole"},
    "Falafel": {"falafel", "sambusak", "pakora", "meatballs", "arancini"},
    "Shawarma": {"shawarma wrap", "chicken shawarma", "beef shawarma", "doner kebab", "gyro", "kathi roll"},
    "Shakshouka": {"shakshuka", "menemen", "huevos rancheros", "chilaquiles", "egg curry"},
    "Tabbouleh": {"tabbouleh", "fattoush salad", "side salad", "greek salad", "garden salad"},
    "Kebab": {"kebab platter", "shish kebab", "kofta kebab", "seekh kebab", "persian kebab koobideh", "iskender kebab", "doner kebab"},
    "Baklava": {"baklava", "kunafa", "basbousa", "halva", "strudel"},
    "Mansaf": {"mansaf", "maqluba", "kabsa", "machboos", "biryani rice"},
    "Ghormeh sabzi": {"ghormeh sabzi", "fesenjan", "ash reshteh", "dal tadka", "saag"},
    "Lahmacun": {"lahmacun", "pide", "manakish", "margherita pizza", "neapolitan pizza"},

    # --- African ---
    "Injera": {"injera with wot", "doro wat", "shiro", "misir wot", "tibs", "thali platter", "ethiopian food platter", "ethiopian chicken stew", "ethiopian lentil stew"},
    "Doro wat": {"doro wat", "injera with wot", "misir wot", "tibs", "shiro", "ethiopian chicken stew", "ethiopian lentil stew", "ethiopian food platter"},
    "Jollof rice": {"jollof rice", "fried rice", "thai fried rice", "pulao", "paella", "seafood paella", "kabsa", "biryani rice", "west african jollof rice", "nigerian party rice", "waakye"},
    "Egusi soup": {"egusi soup", "shiro", "misir wot", "callaloo", "saag", "palak paneer", "melon seed soup", "okra soup", "ogbono soup", "nigerian soup with fufu"},
    "Fufu": {"fufu", "puttu", "appam", "mashed potatoes", "pounded yam", "eba", "amala", "banku", "ugali", "nigerian soup with fufu"},
    "Suya": {"suya skewers", "satay skewers", "shish kebab", "anticuchos", "seekh kebab", "nyama choma", "grilled goat meat"},
    "Tagine": {"tagine", "lamb tagine", "harira soup", "goat curry", "massaman curry"},
    "Couscous": {"couscous", "couscous grain", "bulgur", "quinoa", "tagine"},
    "Bobotie": {"bobotie", "moussaka", "shepherds pie", "cottage pie", "lasagna", "south african curry bake", "cape malay curry"},
    "Koshary": {"koshari", "ful medames", "rajma", "black beans", "lentils", "koshari egyptian"},

    # --- Latin American ---
    "Taco": {"tacos", "carne asada tacos", "al pastor tacos", "fish tacos"},
    "Burrito": {"burrito", "burrito bowl", "wrap", "kathi roll", "shawarma wrap", "quesadilla"},
    "Enchilada": {"enchiladas", "chilaquiles", "tamales", "burrito", "quesadilla"},
    "Guacamole": {"guacamole", "salsa and chips", "hummus", "baba ganoush"},
    "Pozole": {"pozole", "menudo", "sinigang", "harira soup", "black beans"},
    "Mole (sauce)": {"mole poblano", "chicken curry", "butter chicken", "rendang", "korma"},
    "Ceviche": {"ceviche", "poke bowl", "shrimp", "sashimi", "nicoise salad"},
    "Feijoada": {"feijoada", "black beans", "pozole", "ropa vieja", "rajma", "dal makhani"},
    "Empanada": {"empanadas", "samosa", "calzone", "cornish pasty", "pierogi"},
    "Arepa": {"arepas", "pupusas", "tortilla", "pancakes with syrup"},
    "Lomo saltado": {"lomo saltado", "beef and broccoli", "stir fried vegetables", "chow mein"},

    # --- European ---
    "Pizza": {"margherita pizza", "neapolitan pizza", "pepperoni pizza", "calzone", "focaccia"},
    "Carbonara": {"spaghetti carbonara", "cacio e pepe", "fettuccine alfredo", "pasta", "pesto pasta"},
    "Lasagne": {"lasagna", "moussaka", "ravioli", "cottage pie", "shepherds pie"},
    "Risotto": {"risotto", "mushroom risotto", "paella", "congee", "pongal"},
    "Paella": {"seafood paella", "paella", "jollof rice", "fried rice", "biryani rice"},
    "Croissant": {"croissant", "pain au chocolat", "strudel", "scones with cream"},
    "Quiche": {"quiche lorraine", "spanakopita", "pide", "omelette", "frittata"},
    "Moussaka": {"moussaka", "lasagna", "shepherds pie", "cottage pie", "bobotie"},
    "Pierogi": {"pierogi", "dumplings", "gyoza dumplings", "ravioli", "momo dumplings"},
    "Borscht": {"borscht", "tomato soup", "vegetable soup", "minestrone soup", "rasam"},
    "Fish and chips": {"fish and chips", "french fries", "chicken tenders", "tempura", "fried chicken"},
    "Full breakfast": {"full english breakfast", "breakfast burrito", "eggs benedict", "scrambled eggs", "turkish breakfast"},
    "Schnitzel": {"schnitzel", "wiener schnitzel", "tonkatsu", "chicken katsu", "chicken parmesan", "fried chicken"},
    "Goulash": {"goulash", "beef bourguignon", "beef stroganoff", "pot roast", "curry goat"},
    "Gyros": {"gyro", "souvlaki", "doner kebab", "shawarma wrap", "kebab platter"},

    # --- American ---
    "Hamburger": {"hamburger", "cheeseburger", "bacon cheeseburger", "smash burger"},
    "Barbecue": {"bbq ribs", "brisket plate", "pulled pork sandwich", "korean bbq", "asado", "churrasco"},
    "Buffalo wing": {"buffalo wings", "chicken wings", "korean fried chicken", "chicken 65"},
    "Macaroni and cheese": {"mac and cheese", "fettuccine alfredo", "pasta", "cacio e pepe"},
    "Pancake": {"pancakes with syrup", "waffles with berries", "french toast", "crepes", "dutch pancakes"},
    "Caesar salad": {"caesar salad", "cobb salad", "garden salad", "side salad", "salad bowl", "greek salad"},
    "Clam chowder": {"clam chowder", "chicken soup", "vegetable soup", "tomato soup", "corn on the cob"},
    "Cheesecake": {"cheesecake", "panna cotta", "tiramisu", "flan", "tres leches cake"},
}
