import 'package:flutter_test/flutter_test.dart';
import 'package:ipkong/core/climate.dart';
import 'package:ipkong/domain/models/enums.dart';

void main() {
  group('기후대 판정', () {
    test('한국·일본·미국·유럽은 북반구', () {
      for (final tz in [
        'Asia/Seoul',
        'Asia/Tokyo',
        'America/New_York',
        'Europe/London',
        'Asia/Shanghai',
      ]) {
        expect(ClimateResolver.resolve(tz), Climate.northern, reason: tz);
      }
    });

    test('호주·뉴질랜드·남아공·브라질·아르헨티나는 남반구', () {
      for (final tz in [
        'Australia/Sydney',
        'Australia/Melbourne',
        'Pacific/Auckland',
        'Africa/Johannesburg',
        'America/Sao_Paulo',
        'America/Argentina/Buenos_Aires',
      ]) {
        expect(ClimateResolver.resolve(tz), Climate.southern, reason: tz);
      }
    });

    test('싱가포르·자카르타·나이로비는 열대', () {
      for (final tz in [
        'Asia/Singapore',
        'Asia/Jakarta',
        'Africa/Nairobi',
        'America/Bogota',
      ]) {
        expect(ClimateResolver.resolve(tz), Climate.tropical, reason: tz);
      }
    });

    test('Australia/Darwin 은 Australia/ 접두어보다 먼저 열대로 잡힌다', () {
      // 순서를 잘못 두면 남반구로 잘못 분류된다
      expect(ClimateResolver.resolve('Australia/Darwin'), Climate.tropical);
    });

    test('알 수 없는 값은 북반구로 떨어진다', () {
      expect(ClimateResolver.resolve(null), Climate.northern);
      expect(ClimateResolver.resolve(''), Climate.northern);
      expect(ClimateResolver.resolve('Mars/Olympus'), Climate.northern);
    });
  });

  group('겨울 판정', () {
    test('북반구는 11~2월', () {
      for (final m in [11, 12, 1, 2]) {
        expect(
          ClimateResolver.isWinter(DateTime(2026, m, 15), Climate.northern),
          isTrue,
          reason: '$m월',
        );
      }
      for (final m in [3, 6, 9, 10]) {
        expect(
          ClimateResolver.isWinter(DateTime(2026, m, 15), Climate.northern),
          isFalse,
          reason: '$m월',
        );
      }
    });

    test('남반구는 5~8월', () {
      for (final m in [5, 6, 7, 8]) {
        expect(
          ClimateResolver.isWinter(DateTime(2026, m, 15), Climate.southern),
          isTrue,
          reason: '$m월',
        );
      }
      // 남반구의 12월은 한여름이다 — 여기서 틀리면 가장 더울 때 물을 줄인다
      expect(
        ClimateResolver.isWinter(DateTime(2026, 12, 15), Climate.southern),
        isFalse,
      );
    });

    test('열대는 사계절 내내 겨울이 아니다', () {
      for (var m = 1; m <= 12; m++) {
        expect(
          ClimateResolver.isWinter(DateTime(2026, m, 15), Climate.tropical),
          isFalse,
          reason: '$m월',
        );
      }
    });
  });
}
