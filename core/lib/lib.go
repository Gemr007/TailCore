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
	"encoding/json"
	"unsafe"

	"github.com/Gemr007/TailCore/core/tunnel"
)

// Каждая возвращённая наружу строка выделена malloc'ом и принадлежит
// вызывающей стороне: её обязан освободить TailCoreFree.

//export TailCoreStart
func TailCoreStart(config *C.char) *C.char {
	return cError(tunnel.Start(C.GoString(config)))
}

//export TailCoreStop
func TailCoreStop() *C.char {
	return cError(tunnel.Stop())
}

//export TailCoreStatus
func TailCoreStatus() *C.char {
	return C.CString(tunnel.Status())
}

// TailCoreTest блокирует вызывающий поток до конца замера, поэтому звать
// его надо не из потока интерфейса.
//
//export TailCoreTest
func TailCoreTest(config *C.char, timeoutSeconds C.int) *C.char {
	result, err := tunnel.Test(C.GoString(config), int(timeoutSeconds))
	if err != nil {
		// Ошибку отдаём в той же строке, что и результат: на границе C у
		// нас одно возвращаемое значение, и различает их вызывающая
		// сторона по наличию ключа error.
		failure, _ := json.Marshal(map[string]string{"error": err.Error()})
		return C.CString(string(failure))
	}
	return C.CString(result)
}

//export TailCoreFree
func TailCoreFree(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func cError(err error) *C.char {
	if err == nil {
		return nil
	}
	return C.CString(err.Error())
}

func main() {}
