// Пакет собирается в динамическую библиотеку для десктопа
// (`-buildmode=c-shared`): .dll на Windows, .so на Linux, .dylib на macOS.
// Flutter дёргает эти символы через dart:ffi.
//
// Android идёт другим путём — gomobile bind поверх пакета tunnel напрямую,
// без этого файла.
//
// Через границу C ходят только строки: конфиг внутрь, ошибка или статус
// наружу. Отсутствие ошибки — NULL.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"unsafe"

	"github.com/Gemr007/TailCore/core/tunnel"
)

// Каждая возвращённая наружу строка выделена malloc'ом и принадлежит
// вызывающей стороне: её обязан освободить TaleCoreFree.

//export TaleCoreStart
func TaleCoreStart(config *C.char) *C.char {
	return cError(tunnel.Start(C.GoString(config)))
}

//export TaleCoreStop
func TaleCoreStop() *C.char {
	return cError(tunnel.Stop())
}

//export TaleCoreStatus
func TaleCoreStatus() *C.char {
	return C.CString(tunnel.Status())
}

//export TaleCoreFree
func TaleCoreFree(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func cError(err error) *C.char {
	if err == nil {
		return nil
	}
	return C.CString(err.Error())
}

func main() {}
