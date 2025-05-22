#!/bin/bash
set -e

MODULE_NAME="Magisk_DNS_Crypt"
ZIP_NAME="${MODULE_NAME}.zip"

# Очистка старых сборок
rm -f $ZIP_NAME

# Архивация файлов
zip -r $ZIP_NAME META-INF module.prop service.sh post-fs-data.sh customize.sh

echo "Сборка завершена: $ZIP_NAME"
