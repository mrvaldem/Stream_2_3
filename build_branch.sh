#!/bin/bash
# Активация строгого режима:
# -e: прерывание при ошибках
# -u: ошибка при использовании неопределённых переменных
# -o pipefail: возвращает статус последней команды с ошибкой в пайплайне
set -euo pipefail

# Обработчик ошибок для вывода информации о месте возникновения ошибки
trap 'echo "Error in $0 on line $LINENO. Exit code: $?" >&2' ERR

resolve_conflicts() {
    # Принять ВСЕ изменения из cherry-pick (текущего коммита)
    git checkout --theirs . > /dev/null 2>&1
    
    # Удалить файлы с конфликтными маркерами (.orig)
    find . -name "*.orig" -exec rm -f {} \;
    
    # Принудительное удаление системных файлов (игнорируя ошибки если их нет)
    git rm --force --ignore-unmatch src/cf/VERSION src/cf/dumplist.txt 2>/dev/null
}

ensure_branches_exist() {
    # Переключение на master и его обновление
    git checkout -f master
    git pull --quiet origin master

    # Обработка списка веток
    for branch in "$@"; do
        # Проверка существования ветки локально
        if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
            # Попытка создать ветку из origin
            if ! git checkout -b "$branch" "origin/$branch" 2>/dev/null; then
                # Если ветки нет в origin - создать новую от master
                echo "Создание ветки $branch от master"
                git checkout -b "$branch"
                git push -u origin "$branch"
            fi
        fi
        # Принудительное переключение и синхронизация ветки
        git checkout -f "$branch"
        git pull --quiet origin "$branch" || true
    done
}

check_untracked_changes() {
    # Проверка наличия незакоммиченных изменений
    if ! git diff-index --quiet HEAD --; then
        echo "Обнаружены незакоммиченные изменения. Прерывание."
        exit 1
    fi
}

# Основной процесс выполнения скрипта ==========================================

# Проверка рабочей директории
check_untracked_changes

# Создание обязательных веток если их нет
ensure_branches_exist storage_1c branch_sync_hran

# Синхронизация основных веток
for branch in master storage_1c branch_sync_hran; do
    git checkout -f "$branch"
    git pull --quiet origin "$branch"
done

# Получение списка коммитов с фильтром по TASK
git checkout -f branch_sync_hran
logof=$(git log --reverse --grep='TASK' --pretty=format:"%h;%s" storage_1c...branch_sync_hran)
IFS=$'\n' read -d '' -ra commits_list <<< "$logof" || true

# Выход если нет подходящих коммитов
[ ${#commits_list[@]} -eq 0 ] && echo "Нет коммитов с TASK" && exit 0

# Ассоциативный массив для группировки коммитов по TASK-ID
declare -A tasks_map

# Заполнение tasks_map: ключ=TASK-ID, значение=список коммитов
for item in "${commits_list[@]}"; do
    [[ -z "$item" ]] && continue  # Пропуск пустых строк
    
    commit="${item%%;*}"       # Извлечение хеша коммита (до ;)
    message="${item#*;}"      # Извлечение сообщения коммита (после ;)
    
    # Извлечение TASK-ID из сообщения
    task_id=$(echo "$message" | sed -E 's/.*(TASK[^ ]*).*/\1/; t; d' | tr -cd '[:alnum:]._-' | tr ' ' '_')
    [ -z "$task_id" ] && continue  # Пропуск если не найден TASK-ID

    # Добавление коммита в массив задач
    tasks_map["$task_id"]+="$commit "
done

# Обработка каждой задачи
for task_id in "${!tasks_map[@]}"; do
    # Формирование имени ветки (макс. 40 символов)
    branch_name="feature/${task_id:0:40}"
    
    # Получение списка коммитов для задачи
    commits=(${tasks_map["$task_id"]})

    echo "Обработка задачи $task_id (${#commits[@]} коммитов)"

    # Подготовка рабочей ветки
    git checkout -f master  # Возврат на master
    
    # Проверка существования ветки
    if git show-ref --verify "refs/heads/$branch_name" >/dev/null 2>&1; then
        # Переключение на существующую ветку
        git checkout "$branch_name"
        # Синхронизация с удалённым репозиторием
        git pull --quiet origin "$branch_name" || true
    else
        # Создание новой ветки
        git checkout -b "$branch_name"
    fi

    # Применение всех коммитов задачи
    for commit in "${commits[@]}"; do
        # Проверка отсутствия коммита в истории ветки
        
            echo "Добавление коммита $commit в ветку $branch_name"
            
            # Попытка cherry-pick
            if ! git cherry-pick --strategy=recursive -X theirs --allow-empty --keep-redundant-commits "$commit"; then
                # Автоматическое разрешение конфликтов
                echo "Автоматическое разрешение конфликтов для $commit"
                resolve_conflicts
                git add --all
                # Создание коммита с заданным сообщением
                git commit --allow-empty -m "TASK: $task_id ($commit)"
            fi
            
            # Фиксация изменений (включая удаление файлов)
            git rm --force --ignore-unmatch src/cf/VERSION src/cf/dumplist.txt 2>/dev/null || true
            git add --all
            # Обновление коммита без изменения сообщения
            git commit --allow-empty --amend --no-edit 2>/dev/null || true

    done

    # Отправка изменений с безопасным force push
    git push --force-with-lease origin "$branch_name"
done

# Финализация - слияние веток
git checkout branch_sync_hran
git merge --no-ff -X theirs storage_1c -m "Автоматический merge storage_1c"
git push origin branch_sync_hran
git checkout storage_1c

echo "Успешно обработано задач: ${#tasks_map[@]}"