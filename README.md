# ReturnQueue

Репозиторий: [azamat163/ReturnQueue](https://github.com/azamat163/ReturnQueue).

Цель: сделать бесплатный Return Queue для проверки пользы американской аудитории.
Монетизация отложена по решению пользователя; это не подтверждение коммерческого спроса.
Рабочее название приложения — Return Queue. Дата основания: 3 октября 2026 года.

## Что подготовлено

- Spec Kit **1.1.0**, официальный исходный релиз `github/spec-kit@v1.1.0`.
- CLI устанавливается локально в `.tools/spec-kit/`; системный Python не изменяется.
  В исходном ChatGPT workspace также поддерживается установка в `../.tools/spec-kit/`.
- Интеграция Codex: `.agents/skills/`; стандартные шаблоны и сценарии `.specify/`.
- Расширение оценки идей **assess 1.0.1**.
- [Принципы проекта](.specify/memory/constitution.md), версия 1.1.0.
- [Сравнение ниш](docs/niche-shortlist.md) и [план проверки](docs/validation-plan.md).
- [Оценка Return Queue](.specify/assessments/return-queue/decision.md): нужны данные пользователей.
- [Границы работы с возвратами и платежами](docs/return-boundaries.md).
- [Требования бесплатной версии](docs/product-requirements.md): 55 требований, 7 историй.
- [План и 28 задач](specs/001-free-return-prototype/tasks.md); [бесплатный тест пользы](docs/prototype-test-plan.md).
- [Бриф 11 макетов для Figma](docs/figma-design-brief.md).
- [Макет в Figma — 11 экранов](https://www.figma.com/design/SMVZHX6PVpx83cRfqM6S2o/Untitled?node-id=11-93): редактируемые слои и компоненты, English UI, SF Pro. Add/Details реализованы с нативными адаптациями; остальные экраны остаются макетами.
- [Summary, Settings и напоминание для вещи — концепты P2](https://www.figma.com/design/SMVZHX6PVpx83cRfqM6S2o/Untitled?node-id=22-249). Напоминания включаются пользователем и отменяются после сдачи; деньги и store credit в Summary разделены.
- [Превью первого макета из 8 экранов](docs/design/return-queue-preview.png), [превью новых экранов P2](docs/design/return-queue-settings-preview.png); [идентификаторы Figma и проверка](docs/figma-design-state.json).

Первый P1 slice принят после независимого review и проверок: pure Swift модель и строгий portable JSON v1 под
[финальный контракт](specs/001-free-return-prototype/contracts/backup.md).
[JSON schema](specs/001-free-return-prototype/contracts/backup.schema.json) фиксирует форму;
Core проверяет календарные дни, деньги/credit, поля, связи и ручной closure.
Результаты независимого review и проверок — в [verification](specs/001-free-return-prototype/verification.md).
T005 реализует ReturnQueueStorage и actor ReturnStore по
[storage contract](specs/001-free-return-prototype/contracts/storage.md): безопасное
чтение, atomic write, блокировка после read failure и потоковая исходная recovery copy.
Независимые review, native 77/77 XCTest и обе unsigned iOS сборки прошли 4 октября 2026.
Полный backup/restore остаётся T012/T013.
T006 добавляет рабочие Add/edit/details, простую Queue для навигации и Retry/Export
исходных данных при ошибке чтения. Отмена не меняет запись; форма закрывается только
после сохранения на диск. Неизвестные дата/сумма остаются Not set.
Независимые review, native 93/93 теста, unsigned Debug Simulator/Release iOS builds
и все четыре UI-сценария на чистом iPhone 17 / iOS 26.3 прошли 4 октября 2026;
проверены перезапуск, отмена/редактирование, ошибки ввода/записи и Retry/передача исходного файла.
Add/Details сверены с Figma: [нативные адаптации](docs/design/t006-native-mapping.md).
Приняты T001–T006 (6 задач); 22 остаются открытыми. Группировка очереди, сдача/учёт
возмещений, полный backup/restore и P2 ещё впереди. Весь P1 и релиз не завершены.
Синхронизируемые `../sources/` и родительский AGENTS.md остаются справочными материалами.

## Основа разработки iOS

- [Harness вокруг Spec Kit](docs/development-harness.md): три репозиторных навыка
  для работы с требованиями, Swift/iOS и GitLab release.
- [Swift style guide](docs/swift-style-guide.md): официальные Swift API Design Guidelines
  и swiftlang/swift-format; форматирование задаётся `.swift-format`.
- [Архитектура MVVM](docs/ios-architecture.md): SwiftUI, экранные ViewModels,
  единый committed snapshot, Services и независимое ядро.
- [GitLab CI](docs/gitlab-ci.md) и [настройка релиза](docs/release-setup.md): Core quality,
  ручная iOS-сборка и отдельная загрузка TestFlight после настройки runner и подписи.

Локальная проверка: `python3 tooling/harness.py check`; проверка форматирования и
тестов ядра: `python3 tooling/harness.py verify`. Это не подтверждение iOS acceptance
или запуска pipeline в GitLab. Подробности окружения и результаты — в harness guide.

## Использование

Из этой папки:

```sh
./specify version
./specify integration status --json
./specify extension list
```

В Codex, открытом на корне репозитория, навыки вызываются в чате, например:

```text
$speckit-assess-research slug=return-queue
$speckit-specify <задача выбранного продукта>
$speckit-plan <технические ограничения>
$speckit-tasks
$speckit-implement
$speckit-converge
```

Спецификация бесплатного эксперимента готова в specs/001-free-return-prototype/.
Первый Core/JSON slice принят. Текущий этап — T001 минимальный iOS bootstrap с
пройденными review/build/launch gates; далее durable storage, формы/очередь, полный
iOS acceptance и пользовательская проверка пользы.
В исходном ChatGPT workspace корень репозитория находится в папке `app`;
установленные навыки могут потребовать открытия Codex именно на этой папке.
В текущем чате агент может читать их инструкции напрямую; регистрация в интерфейсе
не проверялась.

## Воспроизведение установки

В корне скачанного репозитория, с Python 3.11+:

```sh
python3 -m venv .tools/spec-kit
.tools/spec-kit/bin/python -m pip install --no-cache-dir 'git+https://github.com/github/spec-kit.git@v1.1.0'
./specify version
```

Шаблоны уже установлены; повторная инициализация существующей папки не нужна.
Состояние зависимостей сохранено в `tooling/spec-kit-requirements.txt`.
Документация: [Spec Kit](https://github.com/github/spec-kit),
[интеграция Codex](https://github.github.io/spec-kit/reference/integrations.html).
