# Implementation Plan: Free Return Queue

**Branch**: none | **Date**: 2026-10-03 | **Spec**: [spec.md](spec.md)

**Input**: Бесплатный прототип P1; фото, Summary и Settings/напоминания P2. T001–T008 приняты; Add/edit/details, recovery share и очередь по месту сдачи проверены, остальные P1/P2 workflows впереди.

## Summary

Native iPhone-приложение с локальными записями, очередью по месту сдачи, отдельными
поступлениями денег/кредита, ручным завершением и переносимым архивом. Архитектура
без аккаунтов, серверов, банковских подключений и покупок в приложении.
P2 добавляет Summary по ручным событиям и локальный профиль Settings с общим и
отдельным opt-in напоминаний; готовность P1 от этих экранов не зависит.

## Technical Context

**Language/Version**: Swift 6 language tools; совместимость iOS 17+.
**Primary Dependencies**: SwiftUI/Foundation/Observation; PhotosUI и UserNotifications только P2. iOS 17+; SwiftPM host baseline macOS 14 для actual observable Presentation models.
**Architecture**: SwiftUI + MVVM, экранные @MainActor/@Observable ViewModels,
одна committed app-session snapshot и внедряемые Services; чистое Core.
Границы и порядок durable commit: [ios-architecture.md](../../docs/ios-architecture.md).
**Code conventions**: официальные Swift API Design Guidelines и swiftlang/swift-format;
локальная политика `.swift-format` описана в [style guide](../../docs/swift-style-guide.md).
**Development harness**: репозиторные навыки рядом со Spec Kit и
[локальные проверки](../../docs/development-harness.md).
**CI/distribution**: GitLab, независимые Core quality jobs и настраиваемые ручные
macOS archive/export/TestFlight jobs; [CI](../../docs/gitlab-ci.md),
[release setup](../../docs/release-setup.md). Живой pipeline и iOS release не подтверждены.
**Storage**: версия JSON-модели в Application Support, атомарное сохранение;
P2 — внутренние файлы фото и полный архив с вложениями/локальными настройками;
разрешение устройства не переносится, Summary вычисляется из событий.
**Testing**: XCTest для независимого ядра; iOS integration/UI checks на симуляторе.
**Target Platform**: iPhone, iOS 17+ — принятое рабочее допущение, а не запрос пользователя.
**Project Type**: native mobile app; pure Swift package для проверок ядра.
**Performance Goals**: отображение локального списка до 500 записей без видимой задержки
на поддерживаемом устройстве; измерить перед признанием выполненным.
**Constraints**: offline, USD, ручные даты/возмещения, отсутствие внешних SDK.
**Scale/Scope**: P1 — Queue, Waiting, History, формы/детали и Data & backups;
P2 — фото, Summary, локальные Settings и настройка напоминания вещи. Небольшая
индивидуальная база. P2 навигация: четыре вкладки Queue, Waiting, History, Summary;
Settings открывается шестерёнкой. Новые экраны не повышают приоритет напоминаний и не блокируют P1.
**Environment**: Xcode 26.3 (build 17C529) установлен по
`/Applications/Xcode-26.3.0.app/Contents/Developer`; Apple Swift 6.2.4, iOS SDK 26.2
и симуляторы доступны. Native Core XCTest 49/49 прошли. T001 bootstrap/project
создан; независимые review, unsigned Simulator/Release builds и install/launch
на iPhone 17 / iOS 26.3 прошли 2026-10-04. T005 storage принят после независимого
review, native 77/77 tests и обеих unsigned iOS builds; полные P1 workflows ещё открыты.

## Constitution Check

- Evidence: гипотеза пользы остаётся неподтверждённой; платёжная проверка отложена пользователем.
- Scope: один процесс возврата; P2 отделён, сложные интеграции исключены.
- Data: экспорт/восстановление P1, удаление и защита ошибок обязательны.
- Monetization: все функции бесплатны; никаких тарифов в текущих задачах.
- Verification: ядро проверяется отдельно; устройство требуется для итогового iOS acceptance.

Обновлённые требования требуют сверки дизайна и реализации; публикация и готовность
приложения не подтверждены.

## Project Structure

### Documentation (this feature)

```text
specs/001-free-return-prototype/
  spec.md
  plan.md
  research.md
  data-model.md
  contracts/ui.md
  contracts/backup.md
  contracts/storage.md
  contracts/backup.schema.json
  quickstart.md
  tasks.md
  checklists/requirements.md
```

### Source Code (repository root)

```text
Package.swift                         # Core + Storage + Foundation/Observation Presentation
ReturnQueue/Core/                     # P1 value types и pure archive codec; review/check gates
ReturnQueue/Services/                 # bounded/atomic storage + actor; T005 accepted
ReturnQueue/Presentation/             # shared AppSession + value draft/editor model
ReturnQueue/UI/                       # Queue navigation, Add/edit/details, recovery share
ReturnQueue/Resources/                # named colors + exact Figma package/pin SVGs
ReturnQueue/ReturnQueueApp.swift       # production Application Support storage composition
ReturnQueue.xcodeproj/                # shared app/UI-test scheme, local package products
Tests/ReturnQueueCoreTests/            # P1 records/money/calendar/archive contract checks
Tests/ReturnQueueStorageTests/         # T005 persistence/recovery/failure checks
Tests/ReturnQueuePresentationTests/    # 16 actual session/editor tests
ReturnQueueUITests/                   # 4 isolated simulator workflows + actual disk
```

**First slice boundary**: Точный [JSON v1](contracts/backup.md) и [schema](contracts/backup.schema.json)
предшествуют модели. Core codec не читает файлы; существующий filesystem draft
был перенесён из Core как черновик. T005 заменяет его ReturnQueueStorage и actor
ReturnStore по [storage contract](contracts/storage.md), принятому после независимых
review и verification. Полный restore остаётся открытым.
T001 app bootstrap принят отдельным review/build/launch gate; независимые
T002–T004 не зависят от iOS SDK. Полные P1/P2 workflows остаются
непроверенными до соответствующих задач и device acceptance.
T006 [presentation contract](contracts/presentation.md) принят после независимого
review, 93 native tests, unsigned builds и четырёх simulator UI сценариев.
Это Add/edit/details и recovery share. T007/T008 [queue contract](contracts/queue.md)
принят после отдельных review, native 106 tests, обеих unsigned builds и пяти
fresh-simulator UI сценариев. Pure selector и тонкий MainActor bridge используют
текущий committed snapshot; модель/JSON/Storage/AppSession не меняются.
Progression, полный restore и P2 ещё не приняты.

**Structure Decision**: Core не зависит от UI и iOS-фреймворков; устройство и разрешения
обрабатывает Services, действия пользователя — UI. Не создавать API/backend.

## Complexity Tracking

Исключений из принципов не требуется. Дата без timezone и отдельные reimbursement events
нужны для реальных пограничных случаев. P2-архив не считается готовым, если переносит
только пути к изображениям. Код до спецификации не принимается за готовый фундамент.

## P2: Summary и Settings

Summary selector суммирует Money / Store credit раздельно и считает множество
ReturnItem ID с положительным событием в периоде. This month фильтрует calendar
Date received по текущим году/месяцу; All time использует все события. Статус вещи
и Expected refund не ограничивают участие. Расчёт повторяется после изменения,
удаления и восстановления; производные значения не сохраняются как финансовый источник.

Local settings сохраняет общий выбор уведомлений, default local time 09:00 и
default lead 1 calendar day; каждое напоминание требует отдельного opt-in.
Defaults относятся к новым включаемым событиям, параметры существующих меняются явно.
Return reminder требует Return by и planned; Check refund требует droppedOff и
отдельной ручной даты. Global off/denied permission сохраняют выбор, но отменяют
планирование. Settings показывает фактическое разрешение и preview с причинами
Not scheduled; local profile не содержит auth/email/avatar/backend.

ReminderService согласует только будущие события после правок, смены состояния,
настроек/разрешения, путешествия и restore. CalendarDay остаётся тем же, wall-clock
время пересчитывается для текущего местного часового пояса. Нейтральное уведомление
ведёт в детали по доступному ID, иначе в Queue; фактическая OS-доставка не обещается.
В архиве сохраняются общий выбор и настройки вещей, а разрешение читается на устройстве.

До приёмки P2 нужны проверки Summary, настроек/архива и routing/lifecycle на устройстве.
Контрольное demo: All time $210 money + $80 credit / 4 returns;
Oct 2026 $160 money + $80 credit / 4 returns. Работы и проверки сейчас не выполнены.
