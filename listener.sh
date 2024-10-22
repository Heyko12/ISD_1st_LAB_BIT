#!/bin/bash

# Простой принт в командную строку краткой документации по скрипту
show_help()
{
    echo 'Использовать скрипт можно, исполнив в терминале: sudo sh listener.sh [ФЛАГ]'
    echo
    echo 'ФЛАГИ:'
    echo 'START: Создать демон-процесс для мониторинга, и распечатать в командную строку pid процесса'
    echo 'STOP: Остановить демон-процесс'
    echo 'STATUS: Распечатать статус демон-процесса в командную строку'
}

# Простой греп из "free -mt" с формированием date, после чего все посчитанное будет писаться одной
# строчкой в monitor.csv
monitor()
{
    TOTAL_MEM=$(free -mt | grep "Mem:" | awk '{print $3}')
    MEM="$TOTAL_MEM Мб"

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$timestamp,$MEM" >> monitor.csv
}

# Простая проверка на супер пользователя, user_id=0 означает что мы под ним
su_required()
{
    USER_ID=`id -u`

    if [ "$USER_ID" != "0" ]; then
        echo "Для корректной работы скрипта нужны права супер-пользователя!"
        exit
    fi
}

# Инициирует graceful-выход из демона, удаляя флаг-файл запуска процесса
on_daemon_exit()
{
    if [ -e /var/run/listener.pid ]; then
        rm -f /var/run/listener.pid
    fi

    exit 0
}

# Возвращает содержимое listener.pid флаг-файла
daemon_pid()
{
    if [ -e /var/run/listener.pid ]; then
        echo $(cat /var/run/listener.pid)

        return
    fi

    echo "0"
}

# Проверяем тут, запускал ли кто-либо до нас процесс, пользуемся здесь тем, 
# что созданный нами в фоне процесс (см. daemon_loop) будет откидывать в /var/run специальный файл,
# в котором записан айди порожденного процесса
daemon_running()
{
    if [ -e /var/run/listener.pid ]; then
        echo "1"
        return
    fi

    echo "0"
}

# Здесь мы запускаем демон-процесс, сначала проверяем что на это у нас есть полномочия,
# потом что демон-процесс не был запущен ранее, после чего очищяем файл мониторинга 
# и запускаем в фоне (посредством -l флага) демон-процесс
start_daemon() 
{
    su_required

    if [ $(daemon_running) = "1" ]; then
        echo "Демон-процесс уже запущен..."
        exit 0
    fi

    rm monitor.csv
    touch monitor.csv

    var1="Время"
    var2="Утилизация памяти в Мб"
    echo "$var1,$var2" >> monitor.csv

    echo "Запуск демон-процесса..."
    nohup bash $0 -l > /dev/null 2>&1 &

    daemon_pid=$!
    echo "Демон-процесс запущен с PID=$daemon_pid"
}

# Инициирует graceful-убийство процесса под pid=$daemon_pid, дожидаясь завершения этого процесса
stop_daemon()
{
    su_required

    if [ $(daemon_running) = "0" ]; then
        echo "Демон-процесс уже деактивирован..."
        exit 0
    fi

    echo "Остановка демон-процесса..."

    kill $(daemon_pid)

    while [ -e /var/run/listener.pid ]; do
        continue
    done
}

# Рутина, вызывающаяся посредством применения в программе флага -l, проверяет полномочия поьзователя и то,
# что раньше процесс не был запущен, после чего пишет в директорию /var/run специальный файл, по которому
# скрипт будет понимать что процесс уже был ранее запущен кем-то. Далее, перенаправляет interrupt-сигналы 
# на graceful-exit скрипты, который этот файлик будут очищать, после чего запускает монитор-цикл 
daemon_loop()
{
    su_required

    if [ $(daemon_running) = "1" ]; then
        exit 0
    fi

    echo "$$" > /var/run/listener.pid

    trap 'on_daemon_exit' INT
    trap 'on_daemon_exit' QUIT
    trap 'on_daemon_exit' TERM
    trap 'on_daemon_exit' EXIT

    while true; do
        monitor

        # Мониторинг происходит каждые 5 секунд
        sleep 5
    done
}

# Инициирует проверку статуса демон-сабпроцесса по файлику, которым мы оперируем в данном скрипте,
# достает daemon_pid из него и возвращает в командную строку
daemon_status()
{
    CURRENT_PID=$(daemon_pid)

    if [ $(daemon_running) = "1" ]; then
        echo "Статус: активирован с PID=$CURRENT_PID"
    else
        echo "Статус: деактивирован"
    fi
}

# Обрабатываем тут различные флаги, флаг -l - вспомогательный, под ним будет 
# запускаться фоновый демон-процесс, флаг -h - для обращения к документации
case $1 in
    'START')
        start_daemon
        exit
        ;;
    'STOP')
        stop_daemon
        exit
        ;;
    'STATUS')
        daemon_status
        exit
        ;;
    '-l' )
        # Используется под капотом при выборе опции START
        daemon_loop
        exit
        ;;
    '-h' | * )
        show_help
        exit
        ;;
esac
