// Команда talecore — запуск ядра из командной строки.
// Нужна на этом шаге как единственный способ проверить, что туннель
// действительно поднимается: UI и нативные библиотеки будут позже.
package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/Gemr007/TailCore/core/tunnel"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintf(os.Stderr, "usage: %s <config.json>\n", os.Args[0])
		os.Exit(2)
	}

	config, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, "read config:", err)
		os.Exit(1)
	}

	if err := tunnel.Start(string(config)); err != nil {
		fmt.Fprintln(os.Stderr, "start:", err)
		os.Exit(1)
	}
	fmt.Println(tunnel.Status())

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig

	if err := tunnel.Stop(); err != nil {
		fmt.Fprintln(os.Stderr, "stop:", err)
		os.Exit(1)
	}
	fmt.Println(tunnel.Status())
}
