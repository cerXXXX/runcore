package runcore

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

const meTagXattr = "user.runcore.me"

func (n *Node) ensureMeContactDir() (string, error) {
	if n == nil {
		return "", errors.New("node not started")
	}
	if strings.TrimSpace(n.contactsDir) == "" {
		return "", errors.New("contacts dir is empty")
	}

	name := sanitizeContactFolderName(n.displayName)
	dir := filepath.Join(n.contactsDir, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}

	// Ensure uniqueness: clear tag from other folders.
	entries, _ := os.ReadDir(n.contactsDir)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		if e.Name() == name {
			continue
		}
		p := filepath.Join(n.contactsDir, e.Name())
		if hasXattrTag(p, meTagXattr) {
			_ = clearXattrTag(p, meTagXattr)
		}
	}

	_ = setXattrTag(dir, meTagXattr, []byte("1"))

	n.meDirMu.Lock()
	n.meDir = dir
	n.meDirMu.Unlock()
	return dir, nil
}

func (n *Node) findMeContactDir() (string, error) {
	if n == nil {
		return "", errors.New("node not started")
	}
	n.meDirMu.RLock()
	cached := n.meDir
	n.meDirMu.RUnlock()
	if cached != "" {
		return cached, nil
	}
	if strings.TrimSpace(n.contactsDir) == "" {
		return "", errors.New("contacts dir is empty")
	}

	entries, err := os.ReadDir(n.contactsDir)
	if err != nil {
		return "", err
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		p := filepath.Join(n.contactsDir, e.Name())
		if hasXattrTag(p, meTagXattr) {
			n.meDirMu.Lock()
			n.meDir = p
			n.meDirMu.Unlock()
			return p, nil
		}
	}
	return "", os.ErrNotExist
}

func sanitizeContactFolderName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return "Me"
	}
	name = strings.ReplaceAll(name, string(os.PathSeparator), "_")
	name = strings.ReplaceAll(name, ":", "_")
	name = strings.ReplaceAll(name, "\u0000", "_")
	name = strings.TrimSpace(name)
	if name == "" {
		return "Me"
	}
	if len(name) > 80 {
		return name[:80]
	}
	return name
}

