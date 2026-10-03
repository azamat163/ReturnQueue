# Implementation Plan: Free Return Queue

**Branch**: none | **Date**: 2026-10-03 | **Spec**: [spec.md](spec.md)

**Input**: Бесплатный прототип P1; фото, Summary и Settings/напоминания P2. Текущий этап — требования, план и дизайн.

## Summary

Native iPhone-приложение с локальными записями, очередью по месту сдачи, отдельными
поступлениями денег/кредита, ручным завершением и переносимым архивом. Архитектура
без аккаунтов, серверов, банковских подключений и покупок в приложении.
P2 добавляет Summary по ручным событиям и локальный профиль Settings с общим и
отдельным opt-in напоминаний; готовность P1 от этих экранов не зависит.

## Technical Context

**Language/Version**: Swift 6 language tools; совместимость iOS 17+.
**Primary Dependencies**: SwiftUI/Foundation; PhotosUI и UserNotifications только P2.
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
**Environment**: Swift 6.2.1 доступен; Xcode/симулятор не найдены. iOS-сборку сейчас нельзя
подтвердить. Новые пакеты и установка инструментов в рамках этого этапа не нужны.

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
  quickstart.md
  tasks.md
  checklists/requirements.md
```

### Source Code (repository root)

```text
Package.swift                         # существующий черновик
ReturnQueue/Core/                     # существующий черновик; переделать под spec
ReturnQueue/Services/                 # планируемое хранение/архив/разрешения
ReturnQueue/UI/                       # планируемые формы, очередь, результат, настройки
ReturnQueue/ReturnQueueApp.swift       # планируемая точка входа
ReturnQueue.xcodeproj/                # планируемый проект для Xcode
Tests/ReturnQueueCoreTests/            # черновик проверок, сверить со спецификацией
ReturnQueueUITests/                   # планируемые iOS-сценарии
```

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
