# Tasks: Free Return Queue

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md), contracts/.
**Status**: План реализации; работы не отмечены выполненными по наличию старого черновика.
**Tests**: Проверки прямо требуются FR-044. Приёмка на устройстве отдельна от core tests.
**Organization**: Сначала P1, затем по результатам теста P2. Все функции бесплатны.

## Phase 1: Setup

- [ ] T001 Проверить Xcode/iOS SDK и создать собираемый проект ReturnQueue.xcodeproj и ReturnQueue/ReturnQueueApp.swift; отсутствие SDK записать в quickstart.md.
- [ ] T002 Утвердить Codable JSON v1 и публичный контракт модели в specs/001-free-return-prototype/contracts/backup.md; отделить старый черновик от финальных полей.

## Phase 2: Foundation

- [ ] T003 Привести ReturnQueue/Core/ReturnItem.swift и Money.swift к data-model.md: optional day/amount/location, USD cents, отдельные reimbursement, manual closure и лимиты; создать CalendarDay.swift.

## Phase 3: US1 — Быстро записать возврат

Independent test: минимальная запись без даты/суммы сохраняется и переживает перезапуск.

- [ ] T004 [P] [US1] Написать проверки обязательных текстов, unknown != zero и day-only timezone в Tests/ReturnQueueCoreTests/RecordTests.swift.
- [ ] T005 [US1] Реализовать безопасное чтение/атомарную запись и блокировку при corrupt load в ReturnQueue/Core/ReturnRepository.swift; error состояния в ReturnQueue/Services/ReturnStore.swift.
- [ ] T006 [US1] Создать минимальную форму, детали, отмену и ошибки сохранения в ReturnQueue/UI/ReturnEditor.swift и ReturnDetail.swift.

## Phase 4: US2 — Поездка по местам сдачи

Independent test: три вещи, два магазина, два места; правильные группы/даты/unknown.

- [ ] T007 [P] [US2] Проверить нормализацию мест и стабильный порядок дат в Tests/ReturnQueueCoreTests/QueueTests.swift.
- [ ] T008 [US2] Реализовать grouping selector в ReturnQueue/Core/ReturnQueueSelector.swift и очередь/навигацию в ReturnQueue/UI/QueueView.swift и RootView.swift.

## Phase 5: US3 — Возмещение и ручной итог

Independent test: $50 cash + $30 credit при ожидании $100, затем закрытие с разницей $20.

- [ ] T009 [P] [US3] Проверить деньги, несколько поступлений, credit, unknown expectation, excess и correction в Tests/ReturnQueueCoreTests/RefundTests.swift.
- [ ] T010 [US3] Реализовать расчёт и подтверждаемые переходы в ReturnQueue/Core/RefundSummary.swift и ReturnTransitions.swift без автоматического банковского подтверждения.
- [ ] T011 [US3] Создать формы поступлений/закрытия и Waiting/History в ReturnQueue/UI/ReimbursementEditor.swift, ClosureView.swift, RefundsView.swift и HistoryView.swift.

## Phase 6: US4 — Данные и восстановление

Independent test: полный P1 roundtrip, повторный restore без копий, invalid archive не меняет базу.

- [ ] T012 [P] [US4] Написать проверки unsupported version/duplicate ID/invalid date/size/atomic failure в Tests/ReturnQueueCoreTests/ArchiveTests.swift и PersistenceTests.swift.
- [ ] T013 [US4] Реализовать validated export/preview/atomic replacement и raw corrupt-file export в ReturnQueue/Services/ArchiveService.swift.
- [ ] T014 [US4] Добавить import preview, backup offer, confirm restore/delete и объяснение локального хранения в ReturnQueue/UI/DataSettingsView.swift.

## Phase 7: P1 Verification

- [ ] T015 Проверить и исправить VoiceOver/Dynamic Type, сообщения и отсутствие сетевых/платёжных зависимостей в ReturnQueue/UI/ и ReturnQueue/Services/.
- [ ] T016 Собрать приложение, пройти P1 quickstart и сохранить результаты в specs/001-free-return-prototype/verification.md; unavailable checks нельзя считать passed.

## Phase 8: US5 — Фото (P2)

Independent test: выбрать/отменить фото, экспортировать и восстановить на чистой базе.

- [ ] T017 [US5] Уточнить P2 archive format/migration/limits в specs/001-free-return-prototype/contracts/backup.md до сохранения файлов.
- [ ] T018 [US5] Реализовать single-photo picker, preview/remove, очистку ненужных метаданных и полный media archive в ReturnQueue/Services/AttachmentService.swift и ReturnQueue/UI/ReceiptView.swift.
- [ ] T019 [US5] Проверить отсутствующие media/unsafe path/oversized inputs и portable photo roundtrip в Tests/ReturnQueueCoreTests/MediaArchiveTests.swift и ReturnQueueUITests/ReceiptTests.swift.

## Phase 9: US6 — Напоминания (P2)

Independent test: deny/allow, смена даты, сдача, closure/delete/restore отменяют старые уведомления.

- [ ] T020 [US6] Реализовать сохраняемые настройки и lifecycle notifications в ReturnQueue/Services/ReminderService.swift с нейтральным текстом и будущими датами.
- [ ] T021 [US6] Добавить opt-in и актуальное отображение разрешения в ReturnQueue/UI/ReminderSettingsView.swift.
- [ ] T022 [US6] Проверить cancellation/reschedule/restore/timezone/denied permission в Tests/ReturnQueueCoreTests/ReminderPlanTests.swift и ReturnQueueUITests/ReminderTests.swift.

## Phase 10: Итоговая проверка

- [ ] T023 Обновить README.md и docs/prototype-test-plan.md по реально готовому бесплатному объёму; не добавлять оплату или платный лимит.
- [ ] T024 Проверить P2 после P1 и начать 14-дневный пользовательский тест из specs/001-free-return-prototype/quickstart.md; результаты сохранить в verification.md с числом реальных повторных возвратов.

## Dependencies & Execution Order

T001/T002 -> T003 -> T004–T014 -> T015/T016 = первый прототип.
US2/US3/US4 опираются на одну модель и ReturnStore; changes в общих файлах последовательны.
P2 начинается после P1: US5 T017–T019, US6 T020–T022; итог T023/T024.

## Parallel Examples

После T003 core tester может отдельно делать RecordTests/QueueTests/RefundTests,
а UI agent — формы с фиксированным интерфейсом ReturnStore. Core/persistence agent
владеет ReturnRepository/ArchiveService, не меняя UI. Оркестратор интегрирует.
Не поручать двум агентам одновременно ReturnItem.swift, RootView.swift или schema.
Сценарии P2 не считаются выполненными при наличии одного только pure Swift core.

## Implementation Strategy

Рабочая сборка P1 -> проверка записи/очереди/итога/архива -> тест удобства -> решение
о фото/напоминаниях P2. Корректность данных обязательна до реальных покупок;
пользовательские метрики фиксируются после рабочей сборки, не при завершении документации.
