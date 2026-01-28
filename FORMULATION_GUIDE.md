# Fertilizer Formulation Guide

## For AI Agents Creating Organic Fertilizer Recommendations

This guide provides the knowledge base for AI agents to create effective fertilizer formulations using bioaccumulator plant data.

---

## Understanding NPK Ratios

### What is NPK?

- **N (Nitrogen)**: Promotes leafy green growth, essential for photosynthesis
- **P (Phosphorus)**: Supports root development, flowering, and fruiting
- **K (Potassium)**: Enhances overall plant health, disease resistance, and fruit quality

### Common NPK Ratios by Use Case

| Use Case | NPK Ratio | Description |
|----------|-----------|-------------|
| Balanced general purpose | 10-10-10 or 5-5-5 | Equal nutrients, good for most plants |
| Leafy vegetables | 10-5-5 or 3-1-2 | High nitrogen for leaf production |
| Flowering plants | 5-10-10 or 1-2-2 | Higher P&K for blooms |
| Fruiting crops | 5-10-10 or 5-5-10 | Boost flowering and fruit development |
| Root vegetables | 5-10-10 | Enhanced root growth |
| Lawns (spring) | 20-5-10 | High nitrogen for green growth |
| Lawns (fall) | 10-10-20 | High potassium for winter hardiness |
| Seedlings | 10-20-10 | High phosphorus for root development |
| Compost activator | 20-5-5 | Very high nitrogen to feed bacteria |

---

## Calculating Formulations

### Step 1: Determine Plant Nutrient Content

From the database, extract the average nutrient concentration (% dry weight):

```
Comfrey: N=2.15%, P=0.5%, K=4.4%
Alfalfa: N=2.5%, P=0.55%, K=2.0%
Nettle: N=3.25%, P=0.4%, K=2.0%
```

### Step 2: Calculate NPK Ratio

The NPK ratio is the relative proportion of N:P:K.

**Example**: If a plant has N=3%, P=1%, K=2%
- Total = 3 + 1 + 2 = 6%
- Ratio = 3:1:2 (simplified)
- Commercial notation: "3-1-2" or scaled up "6-2-4"

### Step 3: Mixing Calculations

To achieve a target NPK ratio, mix multiple bioaccumulator sources.

**Example**: Target 5-5-5 (ratio 1:1:1)

**Available Plants**:
- Comfrey: 2.15-0.5-4.4 (ratio 4.3:1:8.8)
- Alfalfa: 2.5-0.55-2.0 (ratio 4.5:1:3.6)

**Strategy**:
1. Comfrey is high in K (potassium)
2. Alfalfa is balanced but needs K boost
3. Need phosphorus supplement (plant sources are typically low in P)

**Formulation**:
```
50% Alfalfa    → Contributes: N=1.25%, P=0.275%, K=1.0%
30% Comfrey    → Contributes: N=0.645%, P=0.15%, K=1.32%
20% Bone meal  → Contributes: N=1%, P=10%, K=0%
                 (scaled to contribution: P=2%)

Total: N≈1.9%, P≈2.4%, K≈2.3%
Ratio: Approximately 1:1.25:1.2 → Close to 5-5-5 target
```

### Step 4: Dry Weight Adjustments

**Important**: Nutrient percentages are based on dry weight, but fresh plant material contains water.

**Moisture Content** (typical):
- Fresh Comfrey: 80-85% water (15-20% dry matter)
- Fresh Nettle: 75-80% water (20-25% dry matter)
- Fresh Clover: 70-80% water (20-30% dry matter)
- Dried plant material: 5-10% water (90-95% dry matter)

**Conversion**:
```
If Comfrey has 2.15% N on dry weight basis:
- 1 kg fresh Comfrey (80% water) = 200g dry matter
- Nitrogen content = 200g × 0.0215 = 4.3g N per kg fresh weight
- Effective fresh-weight N percentage = 0.43%

For calculations, either:
1. Use dry plant material (simplest)
2. Adjust quantities for moisture when using fresh material
```

**AI Agent Recommendation**: Always clarify whether fresh or dried material is being used.

---

## Application Rates

### General Guidelines

| Application Type | Rate per 100 sq ft | Rate per acre |
|------------------|-------------------|---------------|
| Light feeding | 1-2 lbs dry material | 400-800 lbs |
| Moderate feeding | 2-4 lbs dry material | 800-1,600 lbs |
| Heavy feeding | 4-6 lbs dry material | 1,600-2,400 lbs |

### Calculating from Soil Test Results

**Example Scenario**:
- Soil test shows: Need 50 lbs N per acre
- Using dried Nettle (3.25% N)
- Calculation: 50 lbs ÷ 0.0325 = 1,538 lbs dried nettle per acre

### Safety Margins

Always recommend:
- Starting with lower rates for first application
- Waiting 4-6 weeks between heavy applications
- Monitoring plant response
- Soil testing annually

---

## Formulation Templates for AI Agents

### Template 1: High Nitrogen (Leafy Greens)

**Target**: 10-5-5 ratio

**Formulation**:
```json
{
  "name": "High Nitrogen Blend",
  "target_npk": "10-5-5",
  "ingredients": [
    {"plant": "Stinging Nettle", "percentage": 40, "reason": "Highest nitrogen source"},
    {"plant": "Alfalfa", "percentage": 30, "reason": "Balanced nutrients, calcium"},
    {"plant": "Comfrey", "percentage": 20, "reason": "Potassium boost"},
    {"plant": "Kelp meal", "percentage": 10, "reason": "Micronutrients, trace minerals"}
  ],
  "application_rate": "2-3 lbs per 100 sq ft",
  "timing": "Apply before planting, side-dress at 4 weeks",
  "best_for": ["Lettuce", "Spinach", "Kale", "Cabbage"]
}
```

### Template 2: Balanced Garden Fertilizer

**Target**: 5-5-5 ratio

**Formulation**:
```json
{
  "name": "Balanced Garden Blend",
  "target_npk": "5-5-5",
  "ingredients": [
    {"plant": "Alfalfa", "percentage": 35, "reason": "Balanced NPK"},
    {"plant": "Comfrey", "percentage": 25, "reason": "Potassium"},
    {"plant": "Red Clover", "percentage": 20, "reason": "Nitrogen"},
    {"plant": "Kelp meal", "percentage": 10, "reason": "Micronutrients"},
    {"plant": "Rock phosphate", "percentage": 10, "reason": "Phosphorus supplement"}
  ],
  "application_rate": "2-4 lbs per 100 sq ft",
  "timing": "Apply at planting, monthly during growing season",
  "best_for": ["Tomatoes", "Peppers", "Most vegetables"]
}
```

### Template 3: Flowering/Fruiting Boost

**Target**: 5-10-10 ratio

**Formulation**:
```json
{
  "name": "Bloom Booster",
  "target_npk": "5-10-10",
  "ingredients": [
    {"plant": "Comfrey", "percentage": 40, "reason": "High potassium"},
    {"plant": "Bone meal", "percentage": 25, "reason": "Phosphorus for flowering"},
    {"plant": "Kelp meal", "percentage": 15, "reason": "Potassium, micronutrients"},
    {"plant": "Alfalfa", "percentage": 20, "reason": "Balanced base nutrients"}
  ],
  "application_rate": "2-3 lbs per 100 sq ft",
  "timing": "Apply when flower buds appear, repeat every 3 weeks",
  "best_for": ["Roses", "Tomatoes", "Fruiting vegetables", "Berries"]
}
```

### Template 4: Compost Activator

**Target**: High nitrogen (20-5-5)

**Formulation**:
```json
{
  "name": "Compost Activator",
  "target_npk": "20-5-5",
  "ingredients": [
    {"plant": "Fresh Nettle", "percentage": 50, "reason": "Highest nitrogen"},
    {"plant": "Fresh Comfrey", "percentage": 30, "reason": "Additional nutrients"},
    {"plant": "Alfalfa meal", "percentage": 20, "reason": "Protein, nitrogen"}
  ],
  "application_rate": "10 lbs per cubic yard of compost",
  "timing": "Layer throughout compost pile",
  "method": "Mix into compost layers or brew as tea (1:20 ratio)"
}
```

---

## Special Considerations

### Nutrient Release Rates

Different bioaccumulators release nutrients at different rates:

| Plant | Release Rate | Duration |
|-------|--------------|----------|
| Fresh Nettle | Fast (1-2 weeks) | Short-term boost |
| Fresh Comfrey | Medium (2-4 weeks) | Moderate release |
| Dried Alfalfa | Medium-Slow (4-8 weeks) | Sustained feeding |
| Kelp meal | Slow (8-12 weeks) | Long-term availability |

**AI Recommendation Strategy**: Mix fast and slow-release sources for balanced nutrition.

### pH Considerations

Most bioaccumulators have neutral to slightly acidic pH:
- Comfrey: pH 6.5-7.0
- Nettle: pH 6.0-7.0
- Alfalfa: pH 7.0-7.5 (slightly alkaline)

**For Acid-Loving Plants** (blueberries, azaleas):
- Add sulfur or use pine needles
- Avoid excessive alfalfa

**For Alkaline-Preferring Plants**:
- Alfalfa is beneficial
- Add lime if needed

### Micronutrient Considerations

While focusing on NPK, don't forget micronutrients:

**Best Micronutrient Sources**:
- **Kelp/Seaweed**: Iodine, iron, zinc, manganese, trace minerals
- **Nettle**: Iron, calcium, magnesium, silica
- **Comfrey**: Calcium, trace minerals
- **Alfalfa**: Iron, magnesium, calcium

**AI Recommendation**: Always include 5-10% kelp meal for micronutrient coverage.

---

## Quality Indicators for Recommendations

When AI generates formulations, include quality metrics:

```json
{
  "formulation_quality": {
    "npk_match_score": 0.85,
    "explanation": "85% match to target ratio",
    "micronutrient_coverage": "Excellent",
    "cost_effectiveness": "Moderate",
    "availability_score": 0.9,
    "ease_of_use": "Simple - all dried ingredients"
  },
  "confidence_factors": {
    "data_completeness": "High - all ingredients have full NPK data",
    "seasonal_availability": "Year-round for dried materials",
    "regional_suitability": "Temperate climates, zones 4-9"
  }
}
```

---

## Common Pitfalls to Avoid

### For AI Agents - Do NOT:

1. **Recommend excessive nitrogen** (>5% N) for flowering/fruiting plants
   - Causes leafy growth at expense of flowers/fruit

2. **Ignore phosphorus limitations** in plant-based fertilizers
   - Most bioaccumulators are low in P (<1%)
   - Always suggest mineral P supplements for complete nutrition

3. **Forget moisture content** when using fresh materials
   - 1 lb fresh ≠ 1 lb dried
   - Always specify "fresh" or "dried"

4. **Over-application risks**
   - Too much nitrogen can burn plants
   - Recommend starting with lower rates

5. **Ignore timing**
   - Don't fertilize dormant plants
   - Match nutrient type to growth stage

---

## Example AI Response Format

```
User: "I need fertilizer for my tomato plants"

AI Response:

Based on your tomato plants, I recommend a balanced to slightly high-P&K fertilizer
to support flowering and fruiting:

**Formulation: Tomato Power Blend (NPK 5-7-8)**

Ingredients:
• 35% Comfrey (dried) - High potassium for fruit development
• 25% Alfalfa meal - Balanced nutrition, trace minerals
• 20% Bone meal - Phosphorus boost for flowers
• 15% Kelp meal - Micronutrients and growth hormones
• 5% Nettle (dried) - Iron and trace elements

**Application**:
- At planting: 3-4 lbs per 100 sq ft, mixed into soil
- Side-dressing: 2 lbs per 100 sq ft when flowers appear
- Repeat every 3-4 weeks during fruiting

**Expected Results**:
- Strong root development (phosphorus)
- Abundant flowering (phosphorus, potassium)
- Healthy fruit set (potassium, calcium from alfalfa)
- Disease resistance (balanced nutrition)

**Alternative**: If you only have access to Comfrey and Alfalfa, mix 60% Comfrey +
40% Alfalfa and add a commercial organic phosphorus source like bone meal.
```

---

## Advanced: Optimization Algorithms

For sophisticated formulation calculations, AI agents can implement:

### Linear Programming Approach

```python
from scipy.optimize import linprog

def optimize_blend(plants_npk, target_npk, constraints):
    """
    Use linear programming to find optimal plant blend

    Minimize: deviation from target NPK
    Subject to:
        - Sum of percentages = 100%
        - Each percentage >= 0%
        - Each percentage <= 100%
    """
    # Implementation details...
    pass
```

### Genetic Algorithm Approach

```python
def genetic_optimize(plants, target, generations=100):
    """
    Evolve plant combinations toward optimal NPK match

    1. Generate random formulations (population)
    2. Score each by deviation from target
    3. Select best performers
    4. Breed new combinations
    5. Repeat for N generations
    """
    # Implementation details...
    pass
```

---

## Validation Checklist

Before returning a formulation, AI should verify:

- [ ] NPK ratio is appropriate for stated use case
- [ ] All ingredients are available in database
- [ ] Percentages sum to 100%
- [ ] Application rate is safe (not excessive)
- [ ] Timing recommendations match plant growth stage
- [ ] Micronutrient coverage is addressed
- [ ] Special considerations noted (pH, release rate)
- [ ] Alternative options provided if possible

---

## Resources and References

### Nutrient Requirements by Crop

Reference these typical NPK needs:

- **Leafy greens**: High N (3-1-2)
- **Root vegetables**: Moderate N, high P (2-3-2)
- **Fruiting vegetables**: Balanced to high K (2-3-3)
- **Flowers**: Low N, high P&K (1-2-2)
- **Lawns**: High N (4-1-2)

### Organic Matter Content

Bioaccumulators also add valuable organic matter:
- Improves soil structure
- Increases water retention
- Feeds soil microorganisms
- Builds long-term fertility

### Sustainability Notes

Recommend perennial bioaccumulators for sustainable systems:
- **Comfrey**: 20+ year lifespan, multiple harvests/year
- **Alfalfa**: 3-5 year crop, soil improver
- **Nettle**: Perennial, self-sustaining patches

---

## Conclusion

Effective fertilizer formulation using bioaccumulators requires:
1. Accurate nutrient data (from database)
2. Understanding of NPK ratios and plant needs
3. Proper mixing calculations
4. Appropriate application rates and timing
5. Consideration of moisture content, release rates, and micronutrients

AI agents with access to this guide and the bioaccumulator database can provide
sophisticated, customized fertilizer recommendations for organic and sustainable
agriculture.
