//go:build android || darwin || ios || linux

package runcore

import "golang.org/x/sys/unix"

func setXattrTag(path, key string, value []byte) error {
	return unix.Setxattr(path, key, value, 0)
}

func hasXattrTag(path, key string) bool {
	buf := make([]byte, 64)
	n, err := unix.Getxattr(path, key, buf)
	return err == nil && n > 0
}

func clearXattrTag(path, key string) error {
	return unix.Removexattr(path, key)
}
