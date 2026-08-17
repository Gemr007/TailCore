package tunnel

import (
	"context"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

// singBoxEngine — основной движок. Всё, что умеет sing-box, идёт через
// него; Xray подключается только там, где sing-box бессилен.
type singBoxEngine struct {
	instance *box.Box
	traffic  *counter
}

func newSingBoxEngine(configJSON string) (engine, error) {
	ctx := include.Context(context.Background())
	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(configJSON))
	if err != nil {
		return nil, err
	}

	inst, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		return nil, err
	}

	// Счётчик вешаем до старта: соединения, проскочившие между Start и
	// AppendTracker, в статистику бы не попали.
	c := &counter{}
	inst.Router().AppendTracker(c)
	return &singBoxEngine{instance: inst, traffic: c}, nil
}

func (e *singBoxEngine) start() error {
	if err := e.instance.Start(); err != nil {
		// Частично поднятый box держит сокеты — закрываем, иначе следующий
		// старт упрётся в занятый порт.
		e.instance.Close()
		return err
	}
	return nil
}

func (e *singBoxEngine) close() error { return e.instance.Close() }

func (e *singBoxEngine) totals() (int64, int64) { return e.traffic.totals() }
