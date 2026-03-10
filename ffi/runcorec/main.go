package main

/*
#include <stdint.h>
 #include <stdlib.h>
typedef void (*runcore_log_cb)(void* user_data, int32_t level, const char* line);

static inline void runcore_log_cb_call(runcore_log_cb cb, void* user_data, int32_t level, const char* line) {
  cb(user_data, level, line);
}
*/
import "C"

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"unsafe"

	"github.com/svanichkin/go-reticulum/rns"

	"runcore"
)

type nodeHandle struct {
	node *runcore.Node
}

var (
	nextID  uint64 = 1
	nodes          = map[uint64]*nodeHandle{}
	nodesMu sync.RWMutex

	logMu       sync.RWMutex
	logCB       C.runcore_log_cb
	logUserData unsafe.Pointer
)

func main() {}

func allocCString(s string) *C.char { return C.CString(s) }

//export runcore_free_string
func runcore_free_string(p *C.char) {
	if p == nil {
		return
	}
	C.free(unsafe.Pointer(p))
}

//export runcore_default_lxmd_config
func runcore_default_lxmd_config() *C.char {
	return allocCString(runcore.DefaultLXMDConfigText(""))
}

const defaultRNSConfigLogLevel = 4

//export runcore_default_rns_config
func runcore_default_rns_config() *C.char {
	return allocCString(runcore.DefaultRNSConfigText(defaultRNSConfigLogLevel))
}

//export runcore_start
func runcore_start(contactsDir *C.char, sendDir *C.char, messagesDir *C.char, loglevel C.int32_t) C.uint64_t {
	contacts := ""
	if contactsDir != nil {
		contacts = C.GoString(contactsDir)
	}
	send := ""
	if sendDir != nil {
		send = C.GoString(sendDir)
	}
	messages := ""
	if messagesDir != nil {
		messages = C.GoString(messagesDir)
	}
	level := int(loglevel)

	checkDirReadableWritable(contacts)
	checkDirReadableWritable(send)
	checkDirReadableWritable(messages)

	n, err := runcore.Start(runcore.Options{
		Dir:         "",
		ContactsDir: contacts,
		SendDir:     send,
		MessagesDir: messages,
		LogLevel:    level,
	})
	if err != nil {
		return 0
	}

	h := &nodeHandle{node: n}

	nodesMu.Lock()
	id := nextID
	nextID++
	nodes[id] = h
	nodesMu.Unlock()

	return C.uint64_t(id)
}

func checkDirReadableWritable(dir string) {
	dir = strings.TrimSpace(dir)
	if dir == "" {
		return
	}

	p := filepath.Join(dir, ".rwcheck")
	want := []byte("ok")
	if err := os.WriteFile(p, want, 0o644); err != nil {
		return
	}
	got, err := os.ReadFile(p)
	_ = os.Remove(p)
	if err != nil {
		return
	}
	if string(got) != string(want) {
		return
	}
}

func getHandle(id C.uint64_t) *nodeHandle {
	nodesMu.RLock()
	h := nodes[uint64(id)]
	nodesMu.RUnlock()
	return h
}

//export runcore_stop
func runcore_stop(handle C.uint64_t) C.int32_t {
	nodesMu.Lock()
	h := nodes[uint64(handle)]
	delete(nodes, uint64(handle))
	nodesMu.Unlock()
	if h == nil {
		return 0
	}
	_ = h.node.Close()
	return 0
}

//export runcore_set_log_cb
func runcore_set_log_cb(cb C.runcore_log_cb, userData unsafe.Pointer) {
	logMu.Lock()
	logCB = cb
	logUserData = userData
	logMu.Unlock()

	if cb == nil {
		rns.SetLogDestCallback(nil)
		return
	}
	rns.SetLogDestCallback(func(level int, msg string) {
		logMu.RLock()
		c := logCB
		ud := logUserData
		logMu.RUnlock()
		if c == nil {
			return
		}
		cLine := allocCString(msg)
		C.runcore_log_cb_call(c, ud, C.int32_t(level), cLine)
		C.free(unsafe.Pointer(cLine))
	})

	// Emit a marker so clients can verify the hook works without waiting for network activity.
	rns.Log("runcore: log callback enabled", rns.LOG_NOTICE)
}

//export runcore_set_loglevel
func runcore_set_loglevel(level C.int32_t) {
	rns.SetLogLevel(int(level))
}

//export runcore_config_dir
func runcore_config_dir(handle C.uint64_t) *C.char {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return nil
	}
	return allocCString(h.node.ConfigDir())
}

//export runcore_destination_hash_hex
func runcore_destination_hash_hex(handle C.uint64_t) *C.char {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return nil
	}
	return allocCString(h.node.DestinationHashHex())
}

//export runcore_set_display_name
func runcore_set_display_name(handle C.uint64_t, displayName *C.char) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	name := ""
	if displayName != nil {
		name = C.GoString(displayName)
	}
	if err := h.node.SetDisplayName(name); err != nil {
		return 2
	}
	return 0
}

//export runcore_restart
func runcore_restart(handle C.uint64_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	if err := h.node.Restart(); err != nil {
		return 2
	}
	return 0
}

//export runcore_reset_profile
func runcore_reset_profile(handle C.uint64_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	if err := h.node.ResetProfile(); err != nil {
		return 2
	}
	return 0
}

//export runcore_interface_stats_json
func runcore_interface_stats_json(handle C.uint64_t) *C.char {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return nil
	}
	return allocCString(h.node.InterfaceStatsJSON())
}

//export runcore_set_interface_enabled
func runcore_set_interface_enabled(handle C.uint64_t, name *C.char, enabled C.int32_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	if name == nil {
		return 2
	}
	if err := h.node.SetInterfaceEnabled(C.GoString(name), enabled != 0); err != nil {
		return 3
	}
	return 0
}
