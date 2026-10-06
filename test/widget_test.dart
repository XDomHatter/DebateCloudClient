import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:debate_cloud/routed_apps/login/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Competition', () {
    Competition buildComp({DateTime? start, DateTime? end, DateTime? signupStart, DateTime? signupEnd}) {
      return Competition(
        id: 1,
        name: '测试赛',
        description: 'desc',
        startDate: start,
        endDate: end,
        signupStartDate: signupStart,
        signupEndDate: signupEnd,
        jsonDes: '{}',
      );
    }

    test('fromJson parses all fields', () {
      final comp = Competition.fromJson({
        'id': 7,
        'name': '华语辩论赛',
        'description': '简介',
        'startDate': '2026-09-01',
        'endDate': '2026-09-03',
        'signupStartDate': '2026-08-01',
        'signupEndDate': '2026-08-20',
        'jsonDes': '{}',
      });
      expect(comp.id, 7);
      expect(comp.name, '华语辩论赛');
      expect(comp.startDate, DateTime(2026, 9, 1));
      expect(comp.signupEndDate, DateTime(2026, 8, 20));
    });

    test('fromJson tolerates missing optional fields', () {
      final comp = Competition.fromJson({'id': 1});
      expect(comp.name, '');
      expect(comp.startDate, isNull);
    });

    test('status is derived from dates', () {
      final now = DateTime.now();
      expect(
        buildComp(
          signupStart: now.subtract(const Duration(days: 1)),
          signupEnd: now.add(const Duration(days: 1)),
        ).status,
        CompetitionStatus.signupOpen,
      );
      expect(
        buildComp(start: now.add(const Duration(days: 5)), end: now.add(const Duration(days: 6))).status,
        CompetitionStatus.upcoming,
      );
      expect(
        buildComp(start: now.subtract(const Duration(days: 1)), end: now.add(const Duration(days: 1))).status,
        CompetitionStatus.ongoing,
      );
      expect(
        buildComp(
          start: now.subtract(const Duration(days: 6)),
          end: now.subtract(const Duration(days: 5)),
        ).status,
        CompetitionStatus.finished,
      );
    });
  });

  group('DCRequest / DCResponse', () {
    test('request serializes token and data', () {
      final req = DCRequest.fromJson(UserObj(token: 'tk'), {'a': 1});
      final json = req.toJson();
      expect(json['user'], 'tk');
      expect(json['data'], {'a': 1});
      expect(json['send_time'], isA<int>());
    });

    test('anonymous user sends empty token', () {
      final req = DCRequest.fromJson(UserObj(token: null), {});
      expect(req.toJson()['user'], '');
      expect(UserObj(token: '').isAnonymous, isTrue);
    });
  });

  group('LoginController.isValidEmail', () {
    test('accepts a normal email address', () {
      expect(LoginController.isValidEmail('debater@example.com'), isTrue);
    });

    test('rejects invalid email addresses', () {
      expect(LoginController.isValidEmail(''), isFalse);
      expect(LoginController.isValidEmail('not-an-email'), isFalse);
      expect(LoginController.isValidEmail('a@b'), isFalse);
      expect(LoginController.isValidEmail('a b@c.com'), isFalse);
    });
  });
}
