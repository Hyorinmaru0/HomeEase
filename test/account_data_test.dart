import 'package:flutter_test/flutter_test.dart';
import 'package:homeease/controllers/account_data_controller.dart';
import 'package:homeease/controllers/home_controller.dart';
import 'package:homeease/models/account_data.dart';

import 'fakes.dart';

void main() {
  late MemoryStorage storage;
  late HomeController home;
  late AccountDataController account;
  setUp(() async {
    storage = MemoryStorage();
    account = AccountDataController(
      storage: storage,
      userId: 'alice',
      initialName: 'Alice',
    );
    home = HomeController(
      storage: storage,
      gateway: FakeGateway(),
      events: account,
    );
    await home.initialize(startTimer: false);
    await account.initialize(home);
  });
  tearDown(() {
    account.dispose();
    home.dispose();
  });
  test(
    'profile, preferences and failed/confirmed activities restore locally',
    () async {
      await account.saveName('Alice Updated');
      await account.savePreference(
        const DevicePreference(
          deviceId: 'mini-tv',
          displayName: 'My TV',
          room: 'Living room',
        ),
      );
      account.commandObserved('mini-tv', true, 'manual', true, DateTime(2026));
      account.commandObserved(
        'bedroom-ac',
        false,
        'voice',
        false,
        DateTime(2026),
      );
      await Future<void>.delayed(Duration.zero);
      final restored = AccountDataController(
        storage: storage,
        userId: 'alice',
        initialName: 'Alice',
      );
      await restored.initialize(home);
      expect(restored.profile.fullName, 'Alice Updated');
      expect(restored.preferences.single.displayName, 'My TV');
      expect(restored.activity.map((a) => a.success), [false, true]);
      expect(home.settings.name, 'Alice Updated');
      restored.dispose();
    },
  );
  test(
    'bounded activity ignores retired IDs and never issues hardware commands',
    () async {
      for (var i = 0; i < 220; i++) {
        account.commandObserved(
          'mini-tv',
          true,
          'manual',
          true,
          DateTime(2026),
        );
      }
      account.commandObserved('fan', true, 'manual', true, DateTime(2026));
      await Future<void>.delayed(Duration.zero);
      expect(account.activity, hasLength(200));
      expect((await storage.read('account'))!['activity'], hasLength(200));
      expect(home.appliances.firstWhere((d) => d.id == 'mini-tv').isOn, false);
    },
  );
  test('failed local saves remain visible and do not claim success', () async {
    storage.failWrites = true;
    await expectLater(account.saveName('New Name'), throwsException);
    expect(account.error, contains('could not be saved'));
    storage.failWrites = false;
    await account.saveName('New Name');
    expect(account.error, isNull);
  });
  test('mismatched account storage cannot be shown as another user', () async {
    await account.saveName('Alice');
    final bob = AccountDataController(
      storage: storage,
      userId: 'bob',
      initialName: 'Bob',
    );
    await expectLater(bob.initialize(home), throwsFormatException);
    bob.dispose();
  });
}
