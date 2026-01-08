package runcore

import (
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/svanichkin/go-lxmf/lxmf"
	"github.com/svanichkin/go-reticulum/rns"
)

const sendLastAttemptXattr = "user.runcore.send_last_attempt"

func (n *Node) startSendWatchdog() {
	if n == nil {
		return
	}
	if n.announceStop == nil {
		n.announceStop = make(chan struct{})
	}
	sendDir := strings.TrimSpace(n.sendDir)
	if sendDir == "" {
		return
	}

	go func() {
		scan := func() { n.scanSendDirOnce() }

		w, err := fsnotify.NewWatcher()
		if err != nil {
			t := time.NewTicker(2 * time.Second)
			defer t.Stop()
			for {
				select {
				case <-t.C:
					scan()
				case <-n.announceStop:
					return
				}
			}
		}
		defer w.Close()

		_ = w.Add(sendDir)

		var debounceMu sync.Mutex
		var debounce *time.Timer
		trigger := func() {
			debounceMu.Lock()
			defer debounceMu.Unlock()
			if debounce != nil {
				debounce.Stop()
			}
			debounce = time.AfterFunc(400*time.Millisecond, scan)
		}

		scan()

		for {
			select {
			case <-n.announceStop:
				return
			case _, ok := <-w.Events:
				if !ok {
					return
				}
				trigger()
			case _, ok := <-w.Errors:
				if !ok {
					return
				}
				// iCloud FS can be flaky; keep a light poll as fallback.
				t := time.NewTicker(3 * time.Second)
				for {
					select {
					case <-t.C:
						scan()
					case <-n.announceStop:
						t.Stop()
						return
					case _, ok := <-w.Errors:
						if !ok {
							t.Stop()
							return
						}
					}
				}
			}
		}
	}()
}

func (n *Node) scanSendDirOnce() {
	if n == nil || n.router == nil {
		return
	}
	sendDir := strings.TrimSpace(n.sendDir)
	if sendDir == "" {
		return
	}

	processRoot := func(root string) {
		entries, err := os.ReadDir(root)
		if err != nil {
			return
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			name := e.Name()
			if strings.HasPrefix(name, ".") {
				continue
			}
			dest := strings.ToLower(strings.TrimSpace(name))
			if dest == "" {
				continue
			}
			if len(dest) != 32 { // destination hash hex
				continue
			}
			n.processSendFolder(dest, filepath.Join(root, name))
		}
	}

	// Scan both the main send dir and the .pending dir (for retries).
	processRoot(sendDir)
	processRoot(filepath.Join(sendDir, ".pending"))
}

func (n *Node) processSendFolder(destHashHex, dir string) {
	// Move into send/.pending/<destHashHex> before processing to avoid duplicates.
	if p := n.ensurePendingSendFolder(destHashHex, dir); p != "" {
		dir = p
	}

	n.normalizeSendFilenames(dir)

	files, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	paths := make([]string, 0, len(files))
	for _, f := range files {
		if f.IsDir() {
			continue
		}
		name := f.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		paths = append(paths, filepath.Join(dir, name))
	}
	sort.Strings(paths)
	if len(paths) == 0 {
		return
	}

	// Prefer sending binary files as attachments; use optional caption.txt as caption if present.
	var captionPath string
	for _, p := range paths {
		if strings.EqualFold(filepath.Base(p), "caption.txt") {
			captionPath = p
			break
		}
	}
	var attachPath string
	attachPaths := make([]string, 0, len(paths))
	for _, p := range paths {
		if strings.EqualFold(filepath.Ext(p), ".txt") {
			continue
		}
		attachPaths = append(attachPaths, p)
	}

	if len(attachPaths) == 0 {
		// Plain text message(s).
		for _, p := range paths {
			if captionPath != "" && p == captionPath {
				continue
			}
			b, err := os.ReadFile(p)
			if err != nil {
				continue
			}
			content := strings.TrimSpace(string(b))
			if content == "" {
				_ = os.Remove(p)
				continue
			}
			title := "msg"
			base := strings.TrimSuffix(filepath.Base(p), filepath.Ext(p))
			if strings.Contains(base, " -- ") {
				if t, _, ok := strings.Cut(base, " -- "); ok {
					t = strings.TrimSpace(t)
					if t != "" {
						title = t
					}
				}
			} else if bt := strings.TrimSpace(base); bt != "" {
				title = bt
			}
			msg, err := n.SendHex(destHashHex, SendOptions{Title: title, Content: content})
			if err != nil {
				rns.Logf(rns.LOG_NOTICE, "send folder: failed dest=%s err=%v", destHashHex, err)
				return
			}
			n.moveSentFileToMessages(destHashHex, p, msg, lxmf.MessageOutbound)
		}
		return
	}

	// Attachment workflow: send each non-txt file; optional single caption.txt applies to all.
	caption := ""
	if captionPath != "" {
		if b, err := os.ReadFile(captionPath); err == nil {
			caption = strings.TrimSpace(string(b))
		}
	}
	for _, attachPath := range attachPaths {
		data, err := os.ReadFile(attachPath)
		if err != nil || len(data) == 0 {
			_ = os.Remove(attachPath)
			continue
		}
		mime := detectAvatarMime(data)
		name := filepath.Base(attachPath)
		info, err := n.StoreOutgoingAttachment(data, mime, name)
		if err != nil || info.HashHex == "" {
			rns.Logf(rns.LOG_NOTICE, "send folder: store attachment failed dest=%s err=%v", destHashHex, err)
			return
		}
		content := formatAttachmentMessage(info.HashHex, info.Mime, info.Name, info.Size, caption)
		msg, err := n.SendHex(destHashHex, SendOptions{Title: "img", Content: content})
		if err != nil {
			rns.Logf(rns.LOG_NOTICE, "send folder: send attachment failed dest=%s err=%v", destHashHex, err)
			return
		}
		n.moveSentFileToMessages(destHashHex, attachPath, msg, lxmf.MessageOutbound)
	}
	if captionPath != "" {
		// Also move caption into messages as a normal text message file.
		n.moveSentFileToMessages(destHashHex, captionPath, nil, 0)
	}
}

func formatAttachmentMessage(hashHex, mime, name string, size int, caption string) string {
	var lines []string
	lines = append(lines, "hash="+strings.TrimSpace(hashHex))
	if strings.TrimSpace(mime) != "" {
		lines = append(lines, "mime="+strings.TrimSpace(mime))
	}
	if strings.TrimSpace(name) != "" {
		lines = append(lines, "name="+strings.TrimSpace(name))
	}
	if size > 0 {
		lines = append(lines, "size="+strconv.Itoa(size))
	}
	lines = append(lines, "caption="+caption)
	return strings.Join(lines, "\n")
}

func (n *Node) ensurePendingSendFolder(destHashHex, currentDir string) string {
	sendDir := strings.TrimSpace(n.sendDir)
	if sendDir == "" {
		return ""
	}
	pendingRoot := filepath.Join(sendDir, ".pending")
	_ = os.MkdirAll(pendingRoot, 0o755)
	pendingDir := filepath.Join(pendingRoot, destHashHex)

	// If we're already in pending/<dest>, keep it.
	if filepath.Clean(currentDir) == filepath.Clean(pendingDir) {
		_ = setXattrTag(pendingDir, sendLastAttemptXattr, []byte(strconv.FormatInt(time.Now().Unix(), 10)))
		return pendingDir
	}

	// If pending already exists, do not rename over it; just process currentDir as-is.
	if st, err := os.Stat(pendingDir); err == nil && st.IsDir() {
		return currentDir
	}

	// Best-effort move into pending to avoid re-processing on watcher ticks.
	if err := os.Rename(currentDir, pendingDir); err != nil {
		return currentDir
	}
	_ = setXattrTag(pendingDir, sendLastAttemptXattr, []byte(strconv.FormatInt(time.Now().Unix(), 10)))
	return pendingDir
}

func hasMessageTimestampPrefix(name string) bool {
	// Expected: "YYYY-MM-DD HH꞉MM" at the beginning (length 17) where ꞉ is U+A789.
	if len(name) < 17 {
		return false
	}
	p := name[:17]
	// yyyy-mm-dd HH꞉MM
	return strings.Contains(p, "꞉") && p[4] == '-' && p[7] == '-' && p[10] == ' '
}

func (n *Node) normalizeSendFilenames(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	prefix := formatMessageMinute(time.Now())
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		oldName := e.Name()
		if strings.HasPrefix(oldName, ".") {
			continue
		}
		if hasMessageTimestampPrefix(oldName) {
			continue
		}
		newName := prefix + " " + oldName
		_ = os.Rename(filepath.Join(dir, oldName), filepath.Join(dir, newName))
	}
}

func (n *Node) moveSentFileToMessages(destHashHex, srcPath string, msg *lxmf.LXMessage, initialState byte) {
	destHashHex = strings.ToLower(strings.TrimSpace(destHashHex))
	srcPath = strings.TrimSpace(srcPath)
	if destHashHex == "" || srcPath == "" {
		return
	}
	root := outboundMessageDir(n.messagesDir, destHashHex)
	if root == "" {
		return
	}
	_ = os.MkdirAll(root, 0o755)

	base := filepath.Base(srcPath)
	dst := filepath.Join(root, base)
	if _, err := os.Stat(dst); err == nil {
		dst = uniquePath(dst)
	}
	if err := os.Rename(srcPath, dst); err != nil {
		// Cross-device/iCloud corner: fallback to copy+remove.
		if err2 := copyFile(srcPath, dst); err2 == nil {
			_ = os.Remove(srcPath)
		}
	}

	id := msgIDHex(msg)
	if id != "" {
		n.trackOutboundMessageFile(id, dst)
		n.setMessageFileStateByMsgID(id, initialState)
	} else if initialState != 0 {
		_ = setXattrTag(dst, messageStateXattr, []byte(strconv.Itoa(int(initialState))))
	}
}
