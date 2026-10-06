import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Friend.remark 解析与展示名', () {
    test('fromJson 解析 remark 字段', () {
      final f = Friend.fromJson({
        'userId': 2,
        'username': 'alice',
        'nickname': '爱丽丝',
        'remark': '辩论搭子',
      });
      expect(f.remark, '辩论搭子');
      expect(f.displayName, '辩论搭子', reason: '备注优先于昵称');
      expect(f.originalName, '爱丽丝');
    });

    test('remark 缺省为空，展示名回退昵称', () {
      final f = Friend.fromJson({'userId': 2, 'username': 'alice', 'nickname': '爱丽丝'});
      expect(f.remark, '');
      expect(f.displayName, '爱丽丝');
      expect(f.originalName, '爱丽丝');
    });

    test('无昵称时展示名回退用户名', () {
      final f = Friend.fromJson({'userId': 2, 'username': 'alice'});
      expect(f.displayName, 'alice');
      expect(f.originalName, 'alice');
    });

    test('备注清空后展示名回退昵称', () {
      final f = Friend.fromJson({
        'userId': 2,
        'username': 'alice',
        'nickname': '爱丽丝',
        'remark': 'x',
      })
        ..remark = '';
      expect(f.displayName, '爱丽丝');
    });
  });

  group('ChatFriendDetail.fromJson', () {
    test('解析 friend / remark / commonGroups', () {
      final d = ChatFriendDetail.fromJson({
        'friend': {
          'userId': 2,
          'username': 'alice',
          'nickname': '爱丽丝',
          'hasAvatar': true,
          'avatarUpdatedAt': '2026-09-13 09:00:00',
          'remark': '辩论搭子',
          'online': true,
        },
        'commonGroups': [
          {
            'groupId': 1,
            'name': '辩论群',
            'ownerId': 1,
            'createdAt': '2026-09-13 10:00:00',
            'memberCount': 5,
          },
        ],
      });
      expect(d.friend.userId, 2);
      expect(d.friend.username, 'alice');
      expect(d.remark, '辩论搭子');
      expect(d.online, isTrue);
      expect(d.commonGroups.length, 1);
      expect(d.commonGroups.first.name, '辩论群');
      expect(d.commonGroups.first.memberCount, 5);
    });

    test('容忍空 data', () {
      final d = ChatFriendDetail.fromJson({});
      expect(d.friend.userId, 0);
      expect(d.remark, '');
      expect(d.online, isFalse);
      expect(d.commonGroups, isEmpty);
    });
  });
}
