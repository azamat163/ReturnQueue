# Проверка первого бесплатного прототипа

Статус: T001–T008 приняты (8 задач, 20 открыты). Add/edit/details, recovery share
и очередь по месту сдачи прошли независимые review, 106 native tests и пять
сценариев на чистом iPhone-симуляторе.
Полные P1/P2 workflows и релиз ещё не готовы.

## Что понадобится

Для package tests — Swift 6+ и macOS 14+ (Observation Presentation). Для iPhone-сборки и сценариев интерфейса — полный Xcode
с iOS 17+ SDK и симулятором или тестовым iPhone. Xcode 26.3 установлен; iOS SDK 26.2
и симуляторы доступны. App target/shared scheme подключает Core/Storage/Presentation;
unsigned builds и UI XCTest прошли независимо (T007/T008 приняты 2026-10-04).

Из корня выбранного рабочего checkout:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun swift test
```

Первый slice проверяет обязательные/неизвестные поля, деньги и store credit,
Gregorian CalendarDay, ручной closure и строгий JSON v1 roundtrip/отказ decode.
T005 отдельно проверяет ReturnQueueStorage/ReturnStore: bounded read, atomic write,
corrupt-save blocking, stale edits и raw recovery copy. Независимые native 77/77 tests
и обе unsigned iOS builds прошли; T005 принят 2026-10-04. T006 добавляет 16 session/editor
tests (общий набор 93) и четыре actual UI cases с перезапуском/отменой/ошибками.
T007/T008 добавляют семь Queue и шесть clock/projection tests (всего 106) и пятый
UI scenario: три вещи для двух мест, сортировка known/unknown, отмена и сохранённая
перегруппировка после edit/relaunch. Точный API — [queue.md](contracts/queue.md).
Полный backup/restore T012/T013 остаётся открытым.
Реальные результаты и ограничения сохраняются в [verification.md](verification.md).
Принятый pure package gate — native XCTest с Apple Swift 6.2.4 в полном Xcode.
Тесты Linux fallback (Swift 6.2.1 Docker) завершались timeout в разных местах;
их причина не установлена, Linux PASS/support не заявляется. Native Core PASS
не заменяет отдельные app build и iPhone acceptance.

Для UI XCTest выбери отдельный чистый симулятор и замени ID ниже; shared scheme
содержит ReturnQueueUITests. Его DEBUG fixtures используют отдельные UUID-папки,
не production-default архив. Signing для simulator проверки не требуется.

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild test \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'platform=iOS Simulator,id=YOUR_ISOLATED_TEST_DEVICE_ID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

## Сценарии P1 на устройстве

1. Первый запуск без сети: объяснение, Add, никаких запросов карты/аккаунта.
2. Создать вещь только с названием и магазином; видны неизвестные дата/сумма/место.
3. Создать три записи для двух мест; проверить группировку и ближайшие даты.
4. Перезапустить приложение; записи и суммы совпадают.
5. Сдать вещь с ожиданием $100, записать $50 cash и $30 credit; результат различает их.
6. Закрыть как Partial refund с пояснением; история показывает разницу $20.
7. Исправить статус, отменить редактирование, удалить после подтверждения.
8. Экспортировать и восстановить; повторный restore не увеличивает число записей.
9. Повреждённый/неизвестный архив отклоняется, сохранённые записи не меняются.
10. При смене часового пояса выбранный календарный дедлайн остаётся тем же.
11. VoiceOver/большой шрифт: доступны поля, ошибки, статусы и основные действия.

## P2 после реализации

Добавить фото, отменить выбор, отказать в доступе, перенести фото с архивом;
включить/отклонить уведомления, изменить дату, закрыть и удалить возврат.
Проверить отмену старых уведомлений и нейтральный текст на экране блокировки.

## Пользовательская польза

Для первого теста 5 пользователей: время создания минимальной записи, завершение
процесса без подсказок, повторное реальное использование. Смотрите SC-001/006 в spec.md.
Не просить оплату и не измерять conversion-to-paid в этом этапе.

## T001 bootstrap build

Проект `ReturnQueue.xcodeproj`, shared scheme `ReturnQueue`, local Core package
product. English пустая Queue без операций и сохранения не является готовым P1.

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/returnqueue-bootstrap-build \
  CODE_SIGNING_ALLOWED=NO build
```

Для unsigned Device build: `-configuration Release -destination 'generic/platform=iOS'`
с отдельной DerivedData. Это не подписанный архив или TestFlight release.
Точные author/independent результаты и simulator smoke — в verification.md.
