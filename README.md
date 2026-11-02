# Magisk_DNS_Crypt / Магиск DNS Crypt

English version / Русская версия

------------------------------------------------------------

## Overview / Обзор

Magisk_DNS_Crypt is a Magisk module for Android that redirects system DNS traffic through a local dnsproxy instance and forwards queries to a selected secure DNS provider over DoH (DNS-over-HTTPS), DNSCrypt, or a custom upstream server.

Magisk_DNS_Crypt — это Magisk-модуль для Android, который перенаправляет системный DNS-трафик через локальный экземпляр dnsproxy и отправляет запросы к выбранному безопасному DNS-серверу через DoH (DNS-over-HTTPS), DNSCrypt или кастомный upstream-сервер.

This project is intended for users who want:
- private DNS routing
- custom DoH endpoints
- fast switching between providers
- more control over Android system DNS behavior

Проект предназначен для пользователей, которым нужно:
- маршрутизировать DNS через приватный или кастомный сервер
- использовать собственные DoH-эндпоинты
- быстро переключаться между провайдерами
- иметь больший контроль над DNS-поведением Android

------------------------------------------------------------

## Features / Возможности

- Local DNS proxy on 127.0.0.1:5353
- Redirects port 53 to local proxy via iptables
- Supports Cloudflare, Google, Comss, and custom DoH
- Bootstrap IP support for custom upstream resolvers
- User-configurable settings file
- Simple start/stop action support
- Easy integration with Magisk modules

- Локальный DNS-прокси на 127.0.0.1:5353
- Перенаправление порта 53 на локальный прокси через iptables
- Поддержка Cloudflare, Google, Comss и кастомного DoH
- Поддержка bootstrap IP для кастомных upstream-резолверов
- Пользовательский файл настроек
- Простой запуск/остановка через action-скрипт
- Легкая интеграция с Magisk-модулями

------------------------------------------------------------

## How it works / Как это работает

The module downloads the dnsproxy binary, creates a configuration file, launches it locally, and redirects outgoing DNS traffic to the local proxy. The proxy then sends requests to the selected DNS provider using HTTPS or DNSCrypt.

Модуль скачивает бинарный файл dnsproxy, создает конфигурационный файл, запускает его локально и перенаправляет исходящий DNS-трафик на локальный прокси. Затем прокси отправляет запросы к выбранному DNS-провайдеру через HTTPS или DNSCrypt.

Typical flow:
1. install module
2. read configuration from /sdcard/Download/MyDoH_Config.txt
3. select DNS server
4. dnsproxy starts on port 5353
5. iptables redirects port 53 traffic
6. DNS queries go through selected secure upstream

Типичный сценарий:
1. установка модуля
2. чтение конфигурации из /sdcard/Download/MyDoH_Config.txt
3. выбор DNS-сервера
4. запуск dnsproxy на порту 5353
5. перенаправление трафика с 53 порта через iptables
6. DNS-запросы идут на выбранный безопасный upstream

------------------------------------------------------------

## Requirements / Требования

- Rooted Android device
- Magisk installed and enabled
- Device architecture supported by dnsproxy
- iptables support
- Internet access for downloading dnsproxy binary

- Rooted Android-устройство
- Установленный и активный Magisk
- Архитектура устройства, поддерживаемая dnsproxy
- Поддержка iptables
- Доступ в интернет для загрузки бинарника dnsproxy

Supported scripts and typical files:
- customize.sh
- action.sh
- module.prop
- MyDoH_Config.txt
- update.json
- build.sh

------------------------------------------------------------

## Installation / Установка

1. Place the module files in a Magisk-compatible module folder.
2. Reboot or reinstall the module using Magisk.
3. Create or edit:
   /sdcard/Download/MyDoH_Config.txt
4. Start the DNS proxy via action script or module startup logic.

1. Поместите файлы модуля в каталог Magisk-модуля.
2. Перезагрузите устройство или переустановите модуль через Magisk.
3. Создайте или отредактируйте файл:
   /sdcard/Download/MyDoH_Config.txt
4. Запустите DNS-прокси через action-скрипт или логику запуска модуля.

Example:
Пример:

```sh
DNS_CHOICE=1
# Cloudflare

# DNS_CHOICE=2
# Google

# DNS_CHOICE=3
# Comss

# DNS_CHOICE=4
# Custom DoH
# CUSTOM_DNS_HOST=https://dns.nextdns.io/XXXX
# CUSTOM_BOOTSTRAP_IP="45.90.28.0,45.90.30.0"