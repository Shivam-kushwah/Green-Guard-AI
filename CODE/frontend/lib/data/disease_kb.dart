/// Agronomic knowledge base for every class the TFLite model can emit.
///
/// This is the shared source of truth for three separate features:
///   * weather risk       - each entry carries the climate window in which the
///                          pathogen actually infects, so the forecast engine
///                          scores real conditions instead of invented numbers
///   * result screen      - threat level and treatment advice
///   * expert + dashboard - human-readable names, pathogen type, notifiability
///
/// Climate windows come from published extension-service thresholds (ICAR and
/// state agri-university advisories, plus the standard literature for each
/// pathogen) rather than guesswork. Each entry notes its source.
library;

/// How dangerous the disease is *if present* - a property of the pathogen,
/// independent of how confident the classifier happened to be.
enum ThreatLevel { none, low, moderate, high, critical }

extension ThreatLevelX on ThreatLevel {
  String get label => switch (this) {
    ThreatLevel.none => 'Healthy',
    ThreatLevel.low => 'Low',
    ThreatLevel.moderate => 'Moderate',
    ThreatLevel.high => 'High',
    ThreatLevel.critical => 'Critical',
  };
}

enum PathogenType { none, fungus, oomycete, bacterium }

extension PathogenTypeX on PathogenType {
  String get label => switch (this) {
    PathogenType.none => '-',
    PathogenType.fungus => 'Fungus',
    PathogenType.oomycete => 'Oomycete (water mould)',
    PathogenType.bacterium => 'Bacterium',
  };
}

/// The weather envelope in which this pathogen can establish an infection.
class InfectionWindow {
  /// Below [tempMin] or above [tempMax] infection effectively stops.
  final double tempMin;
  final double tempOptLow;
  final double tempOptHigh;
  final double tempMax;

  /// Relative humidity (%) at or above which the leaf surface stays wet long
  /// enough for spores to germinate.
  final double humidityThreshold;

  /// Consecutive hours inside the envelope needed before infection takes hold.
  /// Short windows mean explosive diseases; long windows mean slow builders.
  final int sustainedHoursNeeded;

  /// True when rainfall drives spread (splash dispersal / free water).
  /// Powdery mildews are the classic exception: rain suppresses them.
  final bool rainFavours;

  const InfectionWindow({
    required this.tempMin,
    required this.tempOptLow,
    required this.tempOptHigh,
    required this.tempMax,
    required this.humidityThreshold,
    required this.sustainedHoursNeeded,
    this.rainFavours = true,
  });

  /// 0..1 temperature suitability - flat 1.0 across the optimum band, falling
  /// linearly to zero at the absolute limits.
  double tempSuitability(double t) {
    if (t <= tempMin || t >= tempMax) return 0;
    if (t >= tempOptLow && t <= tempOptHigh) return 1;
    if (t < tempOptLow) return (t - tempMin) / (tempOptLow - tempMin);
    return (tempMax - t) / (tempMax - tempOptHigh);
  }
}

class DiseaseInfo {
  final String species;
  final String disease;

  /// Full name an agronomist or officer would recognise.
  final String commonName;
  final String pathogenName;
  final PathogenType pathogenType;
  final ThreatLevel threat;

  /// null for healthy classes - nothing to forecast.
  final InfectionWindow? window;

  final String symptoms;
  final String treatment;
  final String prevention;

  /// Diseases a state agriculture department wants reported immediately.
  final bool notifiable;

  /// Why this matters in Maharashtra specifically.
  final String? regionalNote;

  final String source;

  const DiseaseInfo({
    required this.species,
    required this.disease,
    required this.commonName,
    required this.pathogenName,
    required this.pathogenType,
    required this.threat,
    required this.window,
    required this.symptoms,
    required this.treatment,
    required this.prevention,
    required this.source,
    this.notifiable = false,
    this.regionalNote,
  });

  bool get isHealthy => threat == ThreatLevel.none;

  /// Stable key used in Firestore documents, aggregates and training exports.
  String get key =>
      '${species}_$disease'.toLowerCase().replaceAll(' ', '_');
}

class DiseaseKb {
  DiseaseKb._();

  /// Keyed by 'species|disease' exactly as class_mapping.json spells them, so
  /// a model retrain that adds classes surfaces here as a miss rather than
  /// silently degrading to generic advice.
  static const Map<String, DiseaseInfo> _byLabel = {
    'Generic|Healthy': DiseaseInfo(
      species: 'Generic',
      disease: 'Healthy',
      commonName: 'Healthy leaf',
      pathogenName: '-',
      pathogenType: PathogenType.none,
      threat: ThreatLevel.none,
      window: null,
      symptoms: 'Uniform colour, no lesions, no discolouration on the leaf.',
      treatment: 'No treatment required.',
      prevention:
          'Keep scouting weekly, especially after a spell of humid weather.',
      source: '-',
    ),

    'Generic|Powdery': DiseaseInfo(
      species: 'Generic',
      disease: 'Powdery',
      commonName: 'Powdery mildew',
      pathogenName: 'Erysiphales spp.',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.moderate,
      // Unusual among fungi: needs humidity but NOT free water. Heavy rain
      // washes spores off and suppresses it, hence rainFavours: false.
      window: InfectionWindow(
        tempMin: 10,
        tempOptLow: 20,
        tempOptHigh: 27,
        tempMax: 33,
        humidityThreshold: 50,
        sustainedHoursNeeded: 6,
        rainFavours: false,
      ),
      symptoms:
          'White to grey powdery patches on the upper leaf surface, later '
          'turning the leaf yellow and brittle.',
      treatment:
          'Wettable sulphur 0.2% or a triazole such as hexaconazole 0.1%. '
          'Repeat after 12-15 days if fresh patches keep appearing.',
      prevention:
          'Widen spacing so air moves through the canopy, and avoid excess '
          'nitrogen which pushes the soft growth this fungus prefers.',
      source:
          'Extension threshold: 20-27 C, RH 50-70%, free water not required',
    ),

    'Generic|Rusty': DiseaseInfo(
      species: 'Generic',
      disease: 'Rusty',
      commonName: 'Rust (unspecified host)',
      pathogenName: 'Puccinia / Uromyces spp.',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.moderate,
      window: InfectionWindow(
        tempMin: 8,
        tempOptLow: 15,
        tempOptHigh: 25,
        tempMax: 30,
        humidityThreshold: 85,
        sustainedHoursNeeded: 6,
      ),
      symptoms:
          'Orange to reddish-brown powdery pustules that rub off on a finger.',
      treatment:
          'Mancozeb 0.25% or propiconazole 0.1% at first pustule appearance.',
      prevention:
          'Remove volunteer plants and alternate hosts that carry the fungus '
          'between seasons.',
      source: 'Generic rust: dew-driven, 15-25 C optimum',
    ),

    // ----------------------------- CORN -----------------------------
    'CORN|Healthy': DiseaseInfo(
      species: 'CORN',
      disease: 'Healthy',
      commonName: 'Healthy maize leaf',
      pathogenName: '-',
      pathogenType: PathogenType.none,
      threat: ThreatLevel.none,
      window: null,
      symptoms: 'Deep green strap leaves, no lesions or streaks.',
      treatment: 'No treatment required.',
      prevention: 'Scout again at tasselling, the most vulnerable stage.',
      source: '-',
    ),

    'CORN|Rust': DiseaseInfo(
      species: 'CORN',
      disease: 'Rust',
      commonName: 'Common rust of maize',
      pathogenName: 'Puccinia sorghi',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.moderate,
      window: InfectionWindow(
        tempMin: 10,
        tempOptLow: 16,
        tempOptHigh: 25,
        tempMax: 30,
        humidityThreshold: 95,
        sustainedHoursNeeded: 6,
      ),
      symptoms:
          'Cinnamon-brown oval pustules scattered on both leaf surfaces, '
          'darkening as the crop matures.',
      treatment:
          'Usually not economic to spray below 5% leaf area. Above that, '
          'mancozeb 0.25% or propiconazole 0.1%.',
      prevention: 'Grow resistant hybrids and avoid very late plantings.',
      source: 'P. sorghi: 16-25 C with RH above 95% for 6 h',
    ),

    'CORN|Gray Spot': DiseaseInfo(
      species: 'CORN',
      disease: 'Gray Spot',
      commonName: 'Grey leaf spot',
      pathogenName: 'Cercospora zeae-maydis',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.high,
      // Needs an unusually long wet period, which is why it flares in a
      // monsoon break-and-return pattern rather than under steady rain.
      window: InfectionWindow(
        tempMin: 15,
        tempOptLow: 22,
        tempOptHigh: 30,
        tempMax: 35,
        humidityThreshold: 95,
        sustainedHoursNeeded: 12,
      ),
      symptoms:
          'Long rectangular grey-tan lesions running parallel to the veins '
          'and sharply boxed in by them.',
      treatment:
          'Azoxystrobin 0.1% or pyraclostrobin at early lesion stage. Most '
          'effective when applied before tasselling.',
      prevention:
          'Rotate out of maize for a season and bury residue - the fungus '
          'overwinters in trash left on the surface.',
      source: 'C. zeae-maydis: 22-30 C, RH above 95% for 12 h or more',
    ),

    'CORN|Leaf Blight': DiseaseInfo(
      species: 'CORN',
      disease: 'Leaf Blight',
      commonName: 'Northern corn leaf blight',
      pathogenName: 'Exserohilum turcicum',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.high,
      window: InfectionWindow(
        tempMin: 12,
        tempOptLow: 18,
        tempOptHigh: 27,
        tempMax: 32,
        humidityThreshold: 90,
        sustainedHoursNeeded: 6,
      ),
      symptoms:
          'Long cigar-shaped grey-green lesions, 3-15 cm, that dry to straw '
          'colour and can join up across the whole leaf.',
      treatment:
          'Mancozeb 0.25% or azoxystrobin 0.1%, repeated at 10-12 day '
          'intervals while conditions stay wet.',
      prevention:
          'Resistant hybrids plus crop rotation; destroy infected stubble.',
      source: 'E. turcicum: 18-27 C, 6-18 h leaf wetness',
    ),

    // ---------------------------- POTATO ----------------------------
    'Potato|Healthy': DiseaseInfo(
      species: 'Potato',
      disease: 'Healthy',
      commonName: 'Healthy potato leaf',
      pathogenName: '-',
      pathogenType: PathogenType.none,
      threat: ThreatLevel.none,
      window: null,
      symptoms: 'Even green compound leaves, no spotting or water-soaking.',
      treatment: 'No treatment required.',
      prevention:
          'Watch closely whenever nights turn cool and misty - that is when '
          'late blight arrives.',
      source: '-',
    ),

    'Potato|Late Blight': DiseaseInfo(
      species: 'Potato',
      disease: 'Late Blight',
      commonName: 'Late blight',
      pathogenName: 'Phytophthora infestans',
      pathogenType: PathogenType.oomycete,
      threat: ThreatLevel.critical,
      // Hutton Criteria: two consecutive days each with min temp >= 10 C and
      // >= 6 h at RH >= 90%. The fastest-moving disease in this list.
      window: InfectionWindow(
        tempMin: 7,
        tempOptLow: 12,
        tempOptHigh: 21,
        tempMax: 27,
        humidityThreshold: 90,
        sustainedHoursNeeded: 6,
      ),
      symptoms:
          'Dark water-soaked patches starting at leaf tips and margins, with '
          'a white fuzzy ring on the underside in the morning. A foul smell '
          'from the canopy means it is already advanced.',
      treatment:
          'Act the same day. Metalaxyl plus mancozeb 0.25% as a curative, '
          'then protectant cover. Destroy severely infected plants - do not '
          'compost them.',
      prevention:
          'Certified seed tubers, wide ridges, and never irrigate overhead in '
          'the evening.',
      notifiable: true,
      regionalNote:
          'The disease behind the Irish famine. In a humid spell it can take '
          'a field in under a week, so a same-day advisory matters more here '
          'than for anything else in this list.',
      source: 'Hutton Criteria: min 10 C and 6 h at RH 90%, two days running',
    ),

    'Potato|Early Blight': DiseaseInfo(
      species: 'Potato',
      disease: 'Early Blight',
      commonName: 'Early blight',
      pathogenName: 'Alternaria solani',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.high,
      // Warmer and drier than late blight, driven by alternating wet/dry
      // cycles rather than sustained wetness.
      window: InfectionWindow(
        tempMin: 15,
        tempOptLow: 24,
        tempOptHigh: 29,
        tempMax: 35,
        humidityThreshold: 85,
        sustainedHoursNeeded: 8,
      ),
      symptoms:
          'Brown spots with concentric rings, like a target, starting on the '
          'older lower leaves.',
      treatment:
          'Mancozeb 0.25% or chlorothalonil; switch to azoxystrobin if spots '
          'keep spreading after two sprays.',
      prevention:
          'Keep the crop well fed - early blight hits nitrogen-starved and '
          'stressed plants hardest. Rotate away from tomato and potato.',
      source: 'A. solani: 24-29 C with alternating wet and dry cycles',
    ),

    // --------------------------- SUGARCANE --------------------------
    'SugarCane|Healthy': DiseaseInfo(
      species: 'SugarCane',
      disease: 'Healthy',
      commonName: 'Healthy sugarcane leaf',
      pathogenName: '-',
      pathogenType: PathogenType.none,
      threat: ThreatLevel.none,
      window: null,
      symptoms: 'Long green blades, no streaks, no reddening in the midrib.',
      treatment: 'No treatment required.',
      prevention:
          'Split open one or two canes each month - red rot hides inside the '
          'stalk long before the leaves show it.',
      source: '-',
    ),

    'SugarCane|RedRot': DiseaseInfo(
      species: 'SugarCane',
      disease: 'RedRot',
      commonName: 'Red rot',
      pathogenName: 'Colletotrichum falcatum',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.critical,
      window: InfectionWindow(
        tempMin: 18,
        tempOptLow: 25,
        tempOptHigh: 30,
        tempMax: 35,
        humidityThreshold: 90,
        sustainedHoursNeeded: 8,
      ),
      symptoms:
          'Leaves yellow and dry from the top down. Split the cane lengthwise: '
          'red tissue crossed by white patches, with a sour alcoholic smell, '
          'confirms it.',
      treatment:
          'No effective cure once the stalk is infected. Uproot and burn '
          'affected clumps immediately, and stop irrigation flowing from that '
          'block into clean ones.',
      prevention:
          'Plant resistant varieties, treat setts with carbendazim 0.1% '
          'before planting, and never take seed cane from an affected field.',
      notifiable: true,
      regionalNote:
          'Known as the cancer of sugarcane. Maharashtra is a top sugarcane '
          'state - Kolhapur, Sangli, Solapur, Ahmednagar - so a red rot '
          'cluster is the single most important thing this map can surface '
          'for a state officer.',
      source: 'C. falcatum: 25-30 C, high humidity, worsened by waterlogging',
    ),

    'SugarCane|Bacteria Blight': DiseaseInfo(
      species: 'SugarCane',
      disease: 'Bacteria Blight',
      commonName: 'Bacterial leaf blight / leaf scald',
      pathogenName: 'Xanthomonas albilineans',
      pathogenType: PathogenType.bacterium,
      threat: ThreatLevel.high,
      window: InfectionWindow(
        tempMin: 18,
        tempOptLow: 25,
        tempOptHigh: 30,
        tempMax: 36,
        humidityThreshold: 85,
        sustainedHoursNeeded: 6,
      ),
      symptoms:
          'Narrow white or cream pencil-line streaks running the length of '
          'the blade, with the leaf later scalding and dying back.',
      treatment:
          'Bactericides work poorly. Rogue out infected stools; copper '
          'oxychloride 0.3% only limits further spread.',
      prevention:
          'Hot-water treat setts at 50 C for 2 hours before planting and '
          'disinfect cutting knives between fields.',
      source: 'X. albilineans: 25-30 C, spread by rain splash and tools',
    ),

    // ----------------------------- WHEAT ----------------------------
    'Wheat|Healthy': DiseaseInfo(
      species: 'Wheat',
      disease: 'Healthy',
      commonName: 'Healthy wheat leaf',
      pathogenName: '-',
      pathogenType: PathogenType.none,
      threat: ThreatLevel.none,
      window: null,
      symptoms: 'Uniform green blade, no pustules or streaking.',
      treatment: 'No treatment required.',
      prevention: 'Scout hardest during cool, dewy mornings.',
      source: '-',
    ),

    'Wheat|Yellow Rust': DiseaseInfo(
      species: 'Wheat',
      disease: 'Yellow Rust',
      commonName: 'Yellow / stripe rust',
      pathogenName: 'Puccinia striiformis f. sp. tritici',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.critical,
      // The cool-weather rust. Note the low optimum - driven by cold dewy
      // nights, the opposite of most entries here.
      window: InfectionWindow(
        tempMin: 2,
        tempOptLow: 10,
        tempOptHigh: 15,
        tempMax: 22,
        humidityThreshold: 90,
        sustainedHoursNeeded: 4,
      ),
      symptoms:
          'Bright yellow pustules in neat stripes between the veins. A yellow '
          'dust comes off on your hand or clothes when you walk the field.',
      treatment:
          'Propiconazole 0.1% or tebuconazole at first sign. One timely spray '
          'saves far more than three late ones.',
      prevention:
          'Sow resistant varieties and avoid late sowing, which pushes the '
          'crop into the cool window the fungus wants.',
      notifiable: true,
      regionalNote:
          'Spreads across whole regions on the wind, so a neighbouring-district '
          'report is a genuine early warning rather than just a statistic.',
      source: 'P. striiformis: 10-15 C optimum with dew - a cool-season rust',
    ),

    'Wheat|Brown Rust': DiseaseInfo(
      species: 'Wheat',
      disease: 'Brown Rust',
      commonName: 'Brown / leaf rust',
      pathogenName: 'Puccinia triticina',
      pathogenType: PathogenType.fungus,
      threat: ThreatLevel.high,
      window: InfectionWindow(
        tempMin: 5,
        tempOptLow: 15,
        tempOptHigh: 22,
        tempMax: 30,
        humidityThreshold: 90,
        sustainedHoursNeeded: 4,
      ),
      symptoms:
          'Round orange-brown pustules scattered at random across the upper '
          'leaf surface, not lined up in stripes.',
      treatment: 'Propiconazole 0.1% or mancozeb 0.25% at first appearance.',
      prevention: 'Resistant varieties and timely sowing.',
      source: 'P. triticina: 15-22 C with dew - warmer than yellow rust',
    ),
  };

  static DiseaseInfo? lookup(String species, String disease) =>
      _byLabel['$species|$disease'];

  /// Falls back to a safe "not catalogued" entry so a model retrain that
  /// introduces a new class degrades to a sensible screen instead of crashing.
  static DiseaseInfo resolve(String species, String disease) {
    return lookup(species, disease) ??
        DiseaseInfo(
          species: species,
          disease: disease,
          commonName: disease,
          pathogenName: 'Not yet catalogued',
          pathogenType: PathogenType.none,
          threat: ThreatLevel.moderate,
          window: null,
          symptoms: 'This class is not yet described in the knowledge base.',
          treatment:
              'Send this case for expert review before applying any chemical.',
          prevention: 'Follow general field sanitation.',
          source: 'unknown class - introduced by a model update',
        );
  }

  static List<DiseaseInfo> get all => _byLabel.values.toList();

  /// Diseases (never healthy classes) that can affect a crop - this is what
  /// the weather engine forecasts against.
  static List<DiseaseInfo> forSpecies(String species) => _byLabel.values
      .where(
        (d) => d.species.toLowerCase() == species.toLowerCase() && !d.isHealthy,
      )
      .toList();

  static List<String> get allSpecies =>
      _byLabel.values.map((d) => d.species).toSet().toList();

  static List<DiseaseInfo> get notifiable =>
      _byLabel.values.where((d) => d.notifiable).toList();
}
