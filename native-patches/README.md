# Ядро ProxyYou 4.1.10

Использована версия Hiddify Core v4.1.0 и её закреплённые подмодули. Изменения только в `hiddify-sing-box/common/monitoring/outbound_monitoring.go`: по умолчанию 20 рабочих обработчиков, максимум 20; единственный URL — `https://www.youtube.com/generate_204`; дополнительные запросы определения IP после успешного URL-теста убраны. Они ранее выполнялись внутри проверки задержки и могли менять измеренную задержку по ответу другого сайта.

Патч: `youtube-monitoring.patch`. Применять из корня Hiddify Core командой `git apply /путь/к/youtube-monitoring.patch`. Подмодуль hiddify-sing-box: `0a02b7729f6a211436bb8bdcd8696c283eb27767`; ray2sing: `f58be84e30d946915a1de437fbcc3d3ffca18a23`. Остальные подмодули берутся по ссылкам этой версии.

Пересборка: Go 1.25.6. macOS arm64: `go build -trimpath -ldflags='-w -s -checklinkname=0 -buildid=' -tags=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_naive_outbound,with_conntrack,with_dhcp -buildmode=c-shared -o hiddify-core.dylib ./platform/desktop`.

Android: gomobile/gobind v0.1.11, NDK 28.2.13676358, JDK 17. Команда из корня ядра: `CGO_LDFLAGS='-O2 -g -s -w -Wl,-z,max-page-size=16384' gomobile bind -androidapi=24 -javapkg=com.hiddify.core -libname=hiddify-core -tags=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_naive_outbound,with_conntrack -trimpath -ldflags='-w -s -checklinkname=0 -buildid=' -target=android/arm,android/arm64,android/amd64 -o hiddify-core.aar github.com/sagernet/sing-box/experimental/libbox ./platform/mobile`. Опции `-gcflags 'all=-N -l'` из upstream Makefile намеренно не используются: они отключали оптимизацию и встраивание функций.

Поместить dylib в `hiddify-core/bin/hiddify-core.dylib`, AAR — в `android/app/libs/hiddify-core.aar`. Крупные бинарные зависимости исключены из архива исходников. Автоматическая загрузка исходного официального бинарника без патча вернёт прежний лимит.

Локальная проверка на macOS: из папки приложения `dart --packages=.dart_tool/package_config.json tools/test_core_workers.dart`. Стенд создаёт 60 SOCKS-конфигураций с локальным сервером, измеряет одновременные запросы до ответа сервера и проверяет адрес назначения. Все запросы отклоняются локально, реальные прокси не используются. Настройки системной сети не изменяются.

Лицензии upstream и ограничения на распространение сохраняются; это частная локальная сборка.
