# Implementation Plan: Free Return Queue

**Branch**: none | **Date**: 2026-10-03 | **Spec**: [spec.md](spec.md)

**Input**: Бесплатный прототип P1; фото и уведомления P2. Текущий этап — требования и план.

## Summary

Native iPhone-приложение с локальными записями, очередью по месту сдачи, отдельными
поступлениями денег/кредита, ручным завершением и переносимым архивом. Архитектура
без аккаунтов, серверов, банковских подключений и покупок в приложении.

## Technical Context

**Language/Version**: Swift 6 language tools; совместимость iOS 17+.
**Primary Dependencies**: SwiftUI/Foundation; PhotosUI и UserNotifications только P2.
**Storage**: версия JSON-модели в Application Support, атомарное сохранение;
P2 — внутренние файлы фото и полный архив с вложениями.
**Testing**: XCTest для независимого ядра; iOS integration/UI checks на симуляторе.
**Target Platform**: iPhone, iOS 17+ — принятое рабочее допущение, а не запрос пользователя.
**Project Type**: native mobile app; pure Swift package для проверок ядра.
**Performance Goals**: отображение локального списка до 500 записей без видимой задержки
на поддерживаемом устройстве; измерить перед признанием выполненным.
**Constraints**: offline, USD, ручные даты/возмещения, отсутствие внешних SDK.
**Scale/Scope**: 4 основных экрана P1, небольшая индивидуальная база; P2 не блокирует P1.
**Environment**: Swift 6.2.1 доступен; Xcode/симулятор не найдены. iOS-сборку сейчас нельзя
подтвердить. Новые пакеты и установка инструментов в рамках этого этапа не нужны.

## Constitution Check

- Evidence: гипотеза пользы остаётся неподтверждённой; платёжная проверка отложена пользователем.
- Scope: один процесс возврата; P2 отделён, сложные интеграции исключены.
- Data: экспорт/восстановление P1, удаление и защита ошибок обязательны.
- Monetization: все функции бесплатны; никаких тарифов в текущих задачах.
- Verification: ядро проверяется отдельно; устройство требуется для итогового iOS acceptance.

Проверка требований проходит; публикация и готовность приложения не подтверждены.

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
