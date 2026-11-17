# Files You

Файловый менеджер для Android в стиле Material 3 / Material You. Интерфейс на Flutter,
ядро на Rust (листинг, поиск, статистика памяти, FTP-сервер), связь через `dart:ffi`.

Возможности: вкладки «Локально / Библиотека / Сеть», системная, светлая, тёмная и OLED
темы, Material You, мгновенный поиск по имени и пути, множественный выбор, корзина,
текстовый редактор и редактор кода с подсветкой, просмотр изображений, SVG, Markdown
(GitHub-стиль), HTML, плеер аудио и видео, FTP-доступ с телефона по Wi-Fi.
Работает на Android 6+ (стоковый Android, MIUI/HyperOS, ColorOS/OriginOS, HiOS,
OneUI и другие оболочки, а также HarmonyOS в режиме совместимости с Android-приложениями).

## Сборка на Windows 11

Нужен Android-телефон или эмулятор и около 10 ГБ места.

### 1. Установите инструменты

1. **Git**: https://git-scm.com/download/win
2. **Android Studio**: https://developer.android.com/studio
   При первом запуске поставьте Android SDK. Затем откройте
   *More Actions → SDK Manager → SDK Tools* и отметьте:
   - Android SDK Command-line Tools (latest)
   - Android SDK Build-Tools
   - Android SDK Platform-Tools
   - NDK (Side by side)

   Нажмите Apply.
3. **Flutter SDK**: https://docs.flutter.dev/get-started/install/windows
   Распакуйте, например, в `C:\src\flutter` и добавьте `C:\src\flutter\bin` в `PATH`.
   Не кладите Flutter в `C:\Program Files`.
4. **Rust**: https://rustup.rs (скачайте `rustup-init.exe`). Для установки нужны
   Visual Studio Build Tools с компонентом «Desktop development with C++»; установщик
   сам подскажет, если их нет.

Откройте новое окно PowerShell и проверьте:

```powershell
flutter --version
cargo --version
flutter doctor --android-licenses
flutter doctor
```

В `flutter doctor` для Android toolchain должна быть зелёная галочка. Если Flutter
не видит SDK, укажите путь:

```powershell
flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"
```

### 2. Шрифт и иконка

В `assets\fonts\` должны лежать `Disket-Mono-Regular.ttf` и `Disket-Mono-Bold.ttf`,
в `assets\` — `icon.png` (квадрат, лучше 1024×1024). Если вы получили проект целиком
от автора, всё уже на месте. Если клонировали репозиторий, шрифтов в нём нет
(см. раздел «Шрифт»): положите свои файлы под этими же именами или замените блок
`fonts:` в `pubspec.yaml` на другой шрифт.

### 3. Подготовьте проект

```powershell
cd путь\к\files_you
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

Скрипт можно запускать повторно после обновления проекта: уже добавленные разрешения
не дублируются.

Скрипт создаёт папку `android`, добавляет разрешения в манифест, находит NDK,
собирает Rust-библиотеку для arm64, armv7 и x86_64, ставит зависимости и генерирует
иконки. Первый запуск идёт 5–15 минут.

### 4. Соберите и установите

```powershell
flutter build apk --release
```

Готовый файл: `build\app\outputs\flutter-apk\app-release.apk`.

Установка по USB (на телефоне включите отладку по USB):

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

или просто скопируйте APK на телефон и откройте его.

### 5. Первый запуск

При первом запуске появится экран с кнопкой «Разрешить». На Android 11 и новее она
открывает системную страницу «Доступ ко всем файлам»: включите переключатель для
Files You и вернитесь в приложение. Без этого файлы не будут видны.

## Если что-то не работает

| Симптом | Что делать |
|---|---|
| `NDK не найден` | Установите NDK в SDK Manager или задайте `ANDROID_NDK_HOME` |
| `linker 'link.exe' not found` | Установите Visual Studio Build Tools (C++) и перезапустите PowerShell |
| `cargo ndk` не найден | `cargo install cargo-ndk`, затем снова запустите `setup.ps1` |
| Gradle ругается на лицензии | `flutter doctor --android-licenses` |
| Скрипт запрещён политикой | Запускайте с `-ExecutionPolicy Bypass`, как в примере |
| Ошибка про отсутствующий шрифт | Проверьте имена файлов в `assets\fonts\` |
| Статистика памяти нулевая, FTP не стартует | Rust-библиотека не попала в APK: проверьте, что есть `android\app\src\main\jniLibs\arm64-v8a\libfiles_you_core.so`, и пересоберите |
| Кириллица в пути проекта ломает сборку | Перенесите проект в путь без кириллицы |

## Структура

```
lib/            Flutter-интерфейс
rust/           Rust-ядро (cdylib, C ABI)
scripts/        setup.ps1
assets/         иконка и шрифты
```

Список C-функций ядра: `fy_storage`, `fy_list`, `fy_search`, `fy_scan`,
`fy_ftp_start`, `fy_ftp_stop`, `fy_free` (см. `rust/src/lib.rs` и `lib/core.dart`).

## Что не доделано

- Облака и удалённые службы (Dropbox, Google Drive, OneDrive, Box, SMB, SFTP, WebDAV,
  FTP-клиент): можно добавить запись о месте, но подключения к ним нет.
- FTP-сервер без TLS и только в пассивном режиме. Используйте его в доверенной сети.
- Аватарки разработчиков загружаются из Telegram при открытии экрана «О приложении»
  и требуют интернета.

## Шрифт

Disket Mono принадлежит Mariano Diez (rostype.com). Его лицензия запрещает передавать
шрифт третьим лицам. APK со встроенным шрифтом, выложенный для других, это нарушает.
Поэтому:

- для личной сборки шрифт можно использовать;
- в публичный репозиторий и в публичные релизы шрифт не кладите (файлы уже в `.gitignore`);
- для публичного релиза получите письменное разрешение автора или смените шрифт
  по умолчанию на свободный (например, из семейства с лицензией OFL).

Пользователь может выбрать любой свой `.ttf` в настройках приложения.

## Лицензия

Код проекта распространяется по лицензии Files You Non-Commercial License 1.0
(файл `LICENSE`): код можно использовать, изменять и распространять бесплатно, но
нельзя продавать и зарабатывать на нём. Сторонние компоненты имеют собственные
лицензии, см. `THIRD_PARTY_NOTICES.md`.
