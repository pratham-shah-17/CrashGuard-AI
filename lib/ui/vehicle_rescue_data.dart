/// Offline vehicle rescue data.
/// All data is hardcoded — works with ZERO internet.
/// Covers dangers, extraction steps, and first aid per vehicle type.
library;

class VehicleRescueData {
  final String vehicleType;
  final String icon;
  final String description;
  final List<String> dangers;
  final List<RescueStep> extractionSteps;
  final List<String> firstAidTips;
  final String fuelType;

  const VehicleRescueData({
    required this.vehicleType,
    required this.icon,
    required this.description,
    required this.dangers,
    required this.extractionSteps,
    required this.firstAidTips,
    required this.fuelType,
  });
}

class RescueStep {
  final int stepNumber;
  final String title;
  final String detail;
  final bool isCritical; // Show in red if true

  const RescueStep({
    required this.stepNumber,
    required this.title,
    required this.detail,
    this.isCritical = false,
  });
}

// ─────────────────────────────────────────────
// ALL OFFLINE RESCUE DATA
// ─────────────────────────────────────────────
const Map<String, VehicleRescueData> kVehicleRescueDatabase = {
  'car': VehicleRescueData(
    vehicleType: 'Car / Sedan / Hatchback',
    icon: '🚗',
    fuelType: 'Petrol / Diesel',
    description: 'Standard 4-wheel passenger vehicle',
    dangers: [
      '⛽ Fuel tank is at the REAR — keep flames away from back of car',
      '💥 Airbags may still deploy even after crash — don\'t lean into cabin',
      '🔋 12V battery under hood — avoid touching terminals',
      '🔥 Engine fire risk — if smoke seen, move victim 30m away immediately',
    ],
    extractionSteps: [
      RescueStep(
        stepNumber: 1,
        title: 'Make the scene safe',
        detail:
            'Turn off the engine if accessible. Turn on hazard lights. Place objects 50m behind to warn traffic.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 2,
        title: 'Check if victim is conscious',
        detail:
            'Tap shoulder and shout "Can you hear me?". If no response, call 108 immediately. Do NOT shake them.',
      ),
      RescueStep(
        stepNumber: 3,
        title: 'Do NOT move the victim yet',
        detail:
            'If victim is breathing and not in immediate danger (no fire/flood), keep them still. Moving can worsen spinal injuries.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 4,
        title: 'Open the door safely',
        detail:
            'Pull door handle and simultaneously push door outward with shoulder. For jammed doors, try rear doors first.',
      ),
      RescueStep(
        stepNumber: 5,
        title: 'Support the neck and head',
        detail:
            'Place both hands on either side of victim\'s head. Keep head aligned with spine at ALL times. Ask someone else to help.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 6,
        title: 'Slide victim out horizontally',
        detail:
            'One person holds head, another grips under armpits. Move in one smooth motion. Never twist the spine.',
      ),
      RescueStep(
        stepNumber: 7,
        title: 'Place in recovery position',
        detail:
            'If breathing, place on their side (recovery position) to prevent choking. Keep monitoring until ambulance arrives.',
      ),
    ],
    firstAidTips: [
      '🩸 For bleeding: apply firm pressure with cloth. Don\'t remove it.',
      '🫁 If not breathing: begin CPR — 30 chest compressions + 2 breaths.',
      '🦴 If you suspect broken bones: do NOT straighten them.',
      '🚨 Keep talking to the victim — keep them conscious and calm.',
    ],
  ),

  'truck': VehicleRescueData(
    vehicleType: 'Truck / Lorry / Heavy Vehicle',
    icon: '🚛',
    fuelType: 'Diesel',
    description: 'Heavy goods vehicle, high cab, large fuel tanks',
    dangers: [
      '⛽ LARGE diesel tanks on both sides — fire risk is HIGH',
      '⚡ 24V electrical system — more dangerous than regular cars',
      '🏋️ Cab is very high — falling risk when extracting driver',
      '📦 Cargo may shift and fall — approach from the side carefully',
      '🔧 Air brakes may release suddenly — stay clear of wheels',
    ],
    extractionSteps: [
      RescueStep(
        stepNumber: 1,
        title: 'Approach from the SIDE only',
        detail:
            'Never approach from front (engine fire) or rear (cargo). Come from driver\'s side door angle.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 2,
        title: 'Secure the truck',
        detail:
            'If safe, apply handbrake and place wheel chocks (stones/wood) under tires to prevent rolling.',
      ),
      RescueStep(
        stepNumber: 3,
        title: 'Climb up carefully',
        detail:
            'Use the built-in steps/handles on the cab. Don\'t pull on door handles to climb — they may break.',
      ),
      RescueStep(
        stepNumber: 4,
        title: 'Check driver consciousness',
        detail:
            'Tap and call out. Driver may be trapped by steering wheel. Do NOT force them out.',
      ),
      RescueStep(
        stepNumber: 5,
        title: 'Extraction needs 3+ people',
        detail:
            'One holds head/neck, two support body. Lower driver down cab steps slowly. Never drop.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 6,
        title: 'Move victim 50m away',
        detail:
            'Trucks carry large fuel loads. Move victim far from vehicle in case of fire.',
        isCritical: true,
      ),
    ],
    firstAidTips: [
      '🚨 Call 108 AND fire brigade (101) — truck fires spread fast.',
      '🩸 Truck drivers often hit steering wheel — check chest for injury.',
      '👁️ Check for head injuries — helmet-less impact with windshield is common.',
      '🦺 If cargo has hazmat symbols, stay back and call 112.',
    ],
  ),

  'bike': VehicleRescueData(
    vehicleType: 'Motorcycle / Bike / Scooter',
    icon: '🏍️',
    fuelType: 'Petrol',
    description: 'Two-wheeler, rider likely thrown from vehicle',
    dangers: [
      '⛽ Small fuel tank near engine — can ignite easily',
      '🪖 DO NOT remove helmet — may cause spinal damage',
      '🛣️ Rider likely skidded — check for road rash injuries',
      '🔥 Hot exhaust pipe — avoid touching, can cause burns',
    ],
    extractionSteps: [
      RescueStep(
        stepNumber: 1,
        title: 'Move the bike away first',
        detail:
            'The bike is the fire risk. Push it at least 10m away from the victim before helping.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 2,
        title: 'NEVER remove the helmet',
        detail:
            'Even if victim asks. Helmet removal can cause fatal spinal damage. Only doctors should remove it.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 3,
        title: 'Check breathing through visor',
        detail:
            'Open the visor to check breathing. If vomiting, hold helmet steady and gently tilt to side.',
      ),
      RescueStep(
        stepNumber: 4,
        title: 'Check for road rash',
        detail:
            'Large skin abrasions from skidding. Cover with clean cloth — don\'t clean with water yet.',
      ),
      RescueStep(
        stepNumber: 5,
        title: 'Keep rider still and flat',
        detail:
            'Riders are often thrown and land awkwardly. Assume spinal injury. Keep them flat until help arrives.',
      ),
      RescueStep(
        stepNumber: 6,
        title: 'Keep them warm',
        detail:
            'Shock causes rapid body cooling. Cover with jacket/blanket. Keep talking to them.',
      ),
    ],
    firstAidTips: [
      '🪖 NEVER remove helmet — this is the most important rule for bike accidents.',
      '🦴 Assume broken limbs — don\'t try to straighten or move them.',
      '😮 Shock is common — keep victim lying down, legs slightly elevated.',
      '🩸 Road rash bleeds a lot but is rarely life-threatening — focus on head/spine.',
    ],
  ),

  'ev_car': VehicleRescueData(
    vehicleType: 'Electric Vehicle (EV Car)',
    icon: '⚡',
    fuelType: 'Electric / Battery',
    description: 'Battery-powered car — special electrical hazards',
    dangers: [
      '⚡ HIGH VOLTAGE battery (400-800V) — can be LETHAL if touched',
      '🔥 Lithium battery fires burn at 1000°C and CANNOT be extinguished easily',
      '🌊 If EV is in water — stay away, electric shock risk is EXTREME',
      '💨 Battery fires release toxic gases — stay upwind',
      '🔄 Car may still be "on" even if silent — EVs make no engine noise',
    ],
    extractionSteps: [
      RescueStep(
        stepNumber: 1,
        title: 'DO NOT touch orange cables',
        detail:
            'Orange cables carry high voltage. If you see orange wires exposed — do NOT touch the car at all.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 2,
        title: 'Turn off the car',
        detail:
            'If safe, reach in and press power button. Look for emergency cut-off switch (usually near door sill — bright red/orange).',
      ),
      RescueStep(
        stepNumber: 3,
        title: 'Check for battery damage',
        detail:
            'If battery area (under floor) is visibly damaged or smoking — treat as fire emergency. Move victim 30m away.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 4,
        title: 'Extraction same as regular car',
        detail:
            'Once confirmed safe (no exposed cables, no smoke), extraction steps are same as regular car. Support neck, slide out.',
      ),
      RescueStep(
        stepNumber: 5,
        title: 'If battery catches fire — RUN',
        detail:
            'EV battery fires cannot be put out with normal extinguishers. Move everyone 50m away and call fire brigade 101.',
        isCritical: true,
      ),
    ],
    firstAidTips: [
      '⚡ If victim received electric shock: do not touch them until power is confirmed off.',
      '👁️ Electric shock victims may have internal burns not visible outside.',
      '🫁 Toxic battery fumes — move victim upwind, fresh air is critical.',
      '🚒 Always call fire brigade for EV accidents — even if no visible fire yet.',
    ],
  ),

  'bus': VehicleRescueData(
    vehicleType: 'Bus / Minibus',
    icon: '🚌',
    fuelType: 'Diesel / CNG',
    description: 'Large passenger vehicle, multiple victims likely',
    dangers: [
      '👥 Multiple casualties — prioritize who needs help most (triage)',
      '⛽ Large fuel tank — fire risk is HIGH',
      '💨 CNG buses have gas cylinders — EXPLOSION RISK if ruptured',
      '🚪 Emergency exits at rear and roof — know how to use them',
    ],
    extractionSteps: [
      RescueStep(
        stepNumber: 1,
        title: 'Assess from outside first',
        detail:
            'Count visible victims. Check for fire/smoke. Don\'t rush in — a second casualty helps no one.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 2,
        title: 'Check for CNG cylinders',
        detail:
            'CNG buses have cylindrical tanks on roof or rear. If hissing sound heard — evacuate everyone 100m away immediately.',
        isCritical: true,
      ),
      RescueStep(
        stepNumber: 3,
        title: 'Use emergency exits',
        detail:
            'Red handles at rear door and roof hatch. Push/pull to open. Don\'t wait for front door if jammed.',
      ),
      RescueStep(
        stepNumber: 4,
        title: 'Triage victims — most critical first',
        detail:
            'Walking wounded can help themselves. Focus on unconscious or heavily bleeding victims first.',
      ),
      RescueStep(
        stepNumber: 5,
        title: 'Form human chain for extraction',
        detail:
            'Line up bystanders to pass victims out of windows/exits. One person stabilizes head, others support body.',
      ),
    ],
    firstAidTips: [
      '📞 Call 108 AND 100 — multiple casualties need multiple ambulances.',
      '🏃 Get able-bodied passengers out first — they can then help others.',
      '🔴 Triage: Red = critical (help first), Yellow = serious, Green = walking.',
      '💨 If CNG leak suspected — NO flames, NO phones near the vehicle.',
    ],
  ),

  'auto': VehicleRescueData(
    vehicleType: 'Auto Rickshaw / Tuk-Tuk',
    icon: '🛺',
    fuelType: 'CNG / Petrol / Electric',
    description: '3-wheeler, open sides, common in Indian roads',
    dangers: [
      '💨 CNG autos — check for hissing gas leak sounds',
      '🔓 Open sides mean passengers are often thrown out',
      '⚖️ Autos tip over easily — approach carefully, may be unstable',
      '🔧 Small vehicle = less protection = more severe injuries',
    ],
    extractionSteps: [
      RescueStep(
        stepNumber: 1,
        title: 'Stabilize the auto first',
        detail:
            'Autos tip over easily. Push gently to check stability before leaning in. Ask bystanders to hold it steady.',
      ),
      RescueStep(
        stepNumber: 2,
        title: 'Check all three sides',
        detail:
            'Passengers in autos are often thrown sideways. Check all around the vehicle, not just inside.',
      ),
      RescueStep(
        stepNumber: 3,
        title: 'Driver extraction',
        detail:
            'Driver seat is exposed. Support driver\'s head from behind while helper pulls from front.',
      ),
      RescueStep(
        stepNumber: 4,
        title: 'Passenger extraction',
        detail:
            'Open side means easy access. Support neck, slide passenger out sideways onto flat ground.',
      ),
    ],
    firstAidTips: [
      '🛺 Auto passengers have no seatbelts — expect to find them thrown from vehicle.',
      '🔍 Search radius of 5m around auto for thrown passengers.',
      '🩹 Road rash from open sides is common — cover wounds with clean cloth.',
      '😮 Shock sets in fast in small vehicle accidents — keep victims warm and calm.',
    ],
  ),
};

// Helper to get rescue data by vehicle type key
VehicleRescueData? getRescueData(String vehicleKey) {
  return kVehicleRescueDatabase[vehicleKey];
}

// All vehicle types as list for selection UI
final List<Map<String, String>> kVehicleTypes = [
  {'key': 'car', 'label': 'Car / Sedan', 'icon': '🚗'},
  {'key': 'bike', 'label': 'Bike / Scooter', 'icon': '🏍️'},
  {'key': 'truck', 'label': 'Truck / Lorry', 'icon': '🚛'},
  {'key': 'bus', 'label': 'Bus', 'icon': '🚌'},
  {'key': 'ev_car', 'label': 'Electric Car', 'icon': '⚡'},
  {'key': 'auto', 'label': 'Auto Rickshaw', 'icon': '🛺'},
];
