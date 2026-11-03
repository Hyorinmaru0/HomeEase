abstract final class SupportedDevices {
  static const names = {
    'living-light': 'Living Room Light',
    'bedroom-light': 'Bedroom Light',
    'mini-tv': 'Mini TV (LCD 16×2)',
    'mini-fridge': 'Mini Fridge',
    'living-ac': 'Living Room AC',
    'bedroom-wall-lamp': 'Smart Wall Lamp',
    'bedroom-ac': 'Bedroom AC',
  };
  static const rooms = {
    'living-light': 'living',
    'mini-tv': 'living',
    'mini-fridge': 'living',
    'living-ac': 'living',
    'bedroom-light': 'bedroom',
    'bedroom-wall-lamp': 'bedroom',
    'bedroom-ac': 'bedroom',
  };
  static const kinds = {
    'living-light': 'light',
    'bedroom-light': 'light',
    'mini-tv': 'tv',
    'mini-fridge': 'fridge',
    'living-ac': 'ac',
    'bedroom-wall-lamp': 'wall-lamp',
    'bedroom-ac': 'ac',
  };
  static const defaultWatts = <String, double>{
    'living-light': 12,
    'bedroom-light': 9,
    'mini-tv': 1,
    'mini-fridge': 100,
    'living-ac': 750,
    'bedroom-wall-lamp': 5,
    'bedroom-ac': 500,
  };
  static const lightIds = {
    'living-light',
    'bedroom-light',
    'bedroom-wall-lamp',
  };
  static String canonical(String id) => switch (id) {
    'living-fridge' => 'mini-fridge',
    'bedroom-lamp' => 'bedroom-wall-lamp',
    _ => id,
  };
  static bool safetyTarget(String id) => contains(id) && id != 'mini-fridge';
  static String? modelNote(String id) => switch (id) {
    'mini-fridge' => 'LED power indicator only; no refrigeration. Door opens manually; no door sensing or control.',
    'living-ac' || 'bedroom-ac' => 'LED appliance model only; no real cooling.',
    'bedroom-wall-lamp' => 'Wall-mounted LED lamp.',
    _ => null,
  };
  static bool contains(Object? id) => names.containsKey(id);
}
