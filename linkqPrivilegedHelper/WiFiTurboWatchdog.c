#include "WiFiTurboWatchdog.h"

#include <errno.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/poll.h>
#include <sys/socket.h>
#include <unistd.h>

#define LINKQ_INTERFACE_COUNT 2

static const char *target_interfaces[LINKQ_INTERFACE_COUNT] = {"awdl0", "llw0"};
static pthread_t watchdog_thread;
static atomic_int watchdog_running = 0;
static int wake_pipe[2] = {-1, -1};
/* Serializes start/stop: XPC calls from separate connections can run concurrently. */
static pthread_mutex_t watchdog_control_mutex = PTHREAD_MUTEX_INITIALIZER;

static void set_error(char *buffer, size_t size, const char *format, ...)
{
    if (buffer == NULL || size == 0) {
        return;
    }

    va_list args;
    va_start(args, format);
    vsnprintf(buffer, size, format, args);
    va_end(args);
}

static int interface_index_matches(unsigned short index)
{
    for (int i = 0; i < LINKQ_INTERFACE_COUNT; i++) {
        if (if_nametoindex(target_interfaces[i]) == index) {
            return 1;
        }
    }

    return 0;
}

static int set_interface_up_flag(int socket_fd, const char *interface_name, int up, char *error_buffer, size_t error_buffer_size)
{
    struct ifreq request;
    memset(&request, 0, sizeof(request));
    strlcpy(request.ifr_name, interface_name, IFNAMSIZ);

    if (ioctl(socket_fd, SIOCGIFFLAGS, &request) < 0) {
        set_error(error_buffer, error_buffer_size, "Could not read %s flags: %s", interface_name, strerror(errno));
        return -1;
    }

    short new_flags = request.ifr_flags;
    if (up) {
        new_flags |= IFF_UP;
    } else {
        new_flags &= ~IFF_UP;
    }

    if (new_flags == request.ifr_flags) {
        return 0;
    }

    request.ifr_flags = new_flags;
    if (ioctl(socket_fd, SIOCSIFFLAGS, &request) < 0) {
        set_error(error_buffer, error_buffer_size, "Could not set %s %s: %s", interface_name, up ? "up" : "down", strerror(errno));
        return -1;
    }

    return 0;
}

static int get_interface_is_up(int socket_fd, const char *interface_name, int *is_up, char *error_buffer, size_t error_buffer_size)
{
    struct ifreq request;
    memset(&request, 0, sizeof(request));
    strlcpy(request.ifr_name, interface_name, IFNAMSIZ);

    if (ioctl(socket_fd, SIOCGIFFLAGS, &request) < 0) {
        set_error(error_buffer, error_buffer_size, "Could not read %s flags: %s", interface_name, strerror(errno));
        return -1;
    }

    *is_up = (request.ifr_flags & IFF_UP) != 0;
    return 0;
}

static int apply_all_interfaces(int up, char *error_buffer, size_t error_buffer_size)
{
    int socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (socket_fd < 0) {
        set_error(error_buffer, error_buffer_size, "Could not create ioctl socket: %s", strerror(errno));
        return -1;
    }

    int changed[LINKQ_INTERFACE_COUNT] = {0};
    int original_up[LINKQ_INTERFACE_COUNT] = {0};
    int result = 0;
    int success_count = 0;

    for (int i = 0; i < LINKQ_INTERFACE_COUNT; i++) {
        char local_error[256] = {0};
        if (get_interface_is_up(socket_fd, target_interfaces[i], &original_up[i], local_error, sizeof(local_error)) < 0) {
            set_error(error_buffer, error_buffer_size, "%s", local_error);
            result = -1;
            if (up) {
                continue;
            }
            break;
        }

        if (set_interface_up_flag(socket_fd, target_interfaces[i], up, local_error, sizeof(local_error)) < 0) {
            set_error(error_buffer, error_buffer_size, "%s", local_error);
            result = -1;
            if (up) {
                continue;
            }
            break;
        }
        success_count++;
        changed[i] = 1;
    }

    if (result < 0 && !up) {
        for (int i = 0; i < LINKQ_INTERFACE_COUNT; i++) {
            if (changed[i]) {
                set_interface_up_flag(socket_fd, target_interfaces[i], original_up[i], NULL, 0);
            }
        }
    }

    close(socket_fd);
    if (up && success_count > 0) {
        return 0;
    }

    return result;
}

static void disable_up_target_interfaces_from_route_event(struct if_msghdr *message, int ioctl_socket)
{
    if (!interface_index_matches(message->ifm_index)) {
        return;
    }

    if ((message->ifm_flags & IFF_UP) == 0) {
        return;
    }

    for (int i = 0; i < LINKQ_INTERFACE_COUNT; i++) {
        if (if_nametoindex(target_interfaces[i]) == message->ifm_index) {
            set_interface_up_flag(ioctl_socket, target_interfaces[i], 0, NULL, 0);
            return;
        }
    }
}

static void drain_route_socket(int route_socket, int ioctl_socket)
{
    unsigned char buffer[sizeof(struct rt_msghdr) + sizeof(struct if_msghdr) + 256];

    for (;;) {
        ssize_t length = read(route_socket, buffer, sizeof(buffer));
        if (length < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return;
            }
            return;
        }

        if ((size_t)length < sizeof(struct if_msghdr)) {
            continue;
        }

        struct rt_msghdr *route_message = (struct rt_msghdr *)buffer;
        if (route_message->rtm_type != RTM_IFINFO) {
            continue;
        }

        struct if_msghdr *interface_message = (struct if_msghdr *)buffer;
        disable_up_target_interfaces_from_route_event(interface_message, ioctl_socket);
    }
}

static void *watchdog_main(void *context)
{
    (void)context;

    int route_socket = socket(AF_ROUTE, SOCK_RAW, 0);
    int ioctl_socket = socket(AF_INET, SOCK_DGRAM, 0);
    if (route_socket < 0 || ioctl_socket < 0) {
        if (route_socket >= 0) {
            close(route_socket);
        }
        if (ioctl_socket >= 0) {
            close(ioctl_socket);
        }
        atomic_store(&watchdog_running, 0);
        return NULL;
    }

    int nonblock = 1;
    ioctl(route_socket, FIONBIO, &nonblock);
    apply_all_interfaces(0, NULL, 0);

    struct pollfd descriptors[2];
    descriptors[0].fd = route_socket;
    descriptors[0].events = POLLIN;
    descriptors[1].fd = wake_pipe[0];
    descriptors[1].events = POLLIN;

    while (atomic_load(&watchdog_running)) {
        int poll_result = poll(descriptors, 2, -1);
        if (poll_result < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }

        if (descriptors[1].revents & POLLIN) {
            break;
        }

        if (descriptors[0].revents & POLLIN) {
            drain_route_socket(route_socket, ioctl_socket);
        }
    }

    close(route_socket);
    close(ioctl_socket);
    return NULL;
}

static int start_watchdog(char *error_buffer, size_t error_buffer_size)
{
    if (atomic_load(&watchdog_running)) {
        return apply_all_interfaces(0, error_buffer, error_buffer_size);
    }

    if (pipe(wake_pipe) < 0) {
        set_error(error_buffer, error_buffer_size, "Could not create watchdog wake pipe: %s", strerror(errno));
        return -1;
    }

    atomic_store(&watchdog_running, 1);
    int thread_result = pthread_create(&watchdog_thread, NULL, watchdog_main, NULL);
    if (thread_result != 0) {
        atomic_store(&watchdog_running, 0);
        close(wake_pipe[0]);
        close(wake_pipe[1]);
        wake_pipe[0] = -1;
        wake_pipe[1] = -1;
        set_error(error_buffer, error_buffer_size, "Could not start watchdog thread: %s", strerror(thread_result));
        return -1;
    }

    if (apply_all_interfaces(0, error_buffer, error_buffer_size) < 0) {
        atomic_store(&watchdog_running, 0);
        if (wake_pipe[1] >= 0) {
            char byte = 1;
            (void)write(wake_pipe[1], &byte, sizeof(byte));
        }
        pthread_join(watchdog_thread, NULL);
        close(wake_pipe[0]);
        close(wake_pipe[1]);
        wake_pipe[0] = -1;
        wake_pipe[1] = -1;
        return -1;
    }

    return 0;
}

static int stop_watchdog(char *error_buffer, size_t error_buffer_size)
{
    if (atomic_load(&watchdog_running)) {
        atomic_store(&watchdog_running, 0);
        if (wake_pipe[1] >= 0) {
            char byte = 1;
            (void)write(wake_pipe[1], &byte, sizeof(byte));
        }
        pthread_join(watchdog_thread, NULL);

        if (wake_pipe[0] >= 0) {
            close(wake_pipe[0]);
        }
        if (wake_pipe[1] >= 0) {
            close(wake_pipe[1]);
        }
        wake_pipe[0] = -1;
        wake_pipe[1] = -1;
    }

    return apply_all_interfaces(1, error_buffer, error_buffer_size);
}

int linkq_set_wifi_turbo_watchdog_enabled(int enabled, char *error_buffer, size_t error_buffer_size)
{
    if (error_buffer != NULL && error_buffer_size > 0) {
        error_buffer[0] = '\0';
    }

    pthread_mutex_lock(&watchdog_control_mutex);
    int result = enabled
        ? start_watchdog(error_buffer, error_buffer_size)
        : stop_watchdog(error_buffer, error_buffer_size);
    pthread_mutex_unlock(&watchdog_control_mutex);

    return result;
}
