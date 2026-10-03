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
- [Требования бесплатной версии](docs/product-requirements.md): 45 требований, 6 историй.
- [План и 24 задачи](specs/001-free-return-prototype/tasks.md); [бесплатный тест пользы](docs/prototype-test-plan.md).
- [Бриф шести экранов для Figma](docs/figma-design-brief.md).
- [Макет в Figma — 8 экранов](https://www.figma.com/design/SMVZHX6PVpx83cRfqM6S2o/Untitled?node-id=11-93): редактируемые слои и компоненты, English UI, SF Pro. Это статические макеты; работающего UI пока нет.
- [Превью макета](docs/design/return-queue-preview.png); [идентификаторы Figma и проверка](docs/figma-design-state.json).

Начат pure Swift core до финальной спецификации; он остаётся непроверенным черновиком,
требует приведения к новой модели. iPhone UI и Xcode-проект ещё не созданы. При текущей конфигурации активны Apple Command Line
Tools; сборка iOS и симулятор не проверены. Это не мешает этапу исследования ниши.
Синхронизируемые `../sources/` и родительский AGENTS.md остаются справочными материалами.

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
Текущий этап завершает требования; далее реализовать P1 по задачам и проверить пользу.
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
