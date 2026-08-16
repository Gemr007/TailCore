package tunnel

import (
	"context"
	"net"
	"sync/atomic"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing/common/bufio"
	N "github.com/sagernet/sing/common/network"
)

// counter считает байты, прошедшие через туннель.
//
// Взято не из clash_api и не из v2ray_api: те тянут за собой build-тег,
// HTTP-сервер и порт, который придётся охранять. Роутер sing-box и так
// пускает соединения через AppendTracker, а обёртки-счётчики уже есть в
// sing/common/bufio — остаётся сложить их вместе.
//
// Направления считаются со стороны клиента: чтение из входящего соединения
// это то, что пользователь отправляет (upload), запись в него — то, что он
// получает (download).
type counter struct {
	up   atomic.Int64
	down atomic.Int64
}

var _ adapter.ConnectionTracker = (*counter)(nil)

func (c *counter) RoutedConnection(
	_ context.Context, conn net.Conn,
	_ adapter.InboundContext, _ adapter.Rule, _ adapter.Outbound,
) net.Conn {
	return bufio.NewCounterConn(conn, c.readCount(), c.writeCount())
}

func (c *counter) RoutedPacketConnection(
	_ context.Context, conn N.PacketConn,
	_ adapter.InboundContext, _ adapter.Rule, _ adapter.Outbound,
) N.PacketConn {
	return bufio.NewCounterPacketConn(conn, c.readCount(), c.writeCount())
}

func (c *counter) readCount() []N.CountFunc {
	return []N.CountFunc{func(n int64) { c.up.Add(n) }}
}

func (c *counter) writeCount() []N.CountFunc {
	return []N.CountFunc{func(n int64) { c.down.Add(n) }}
}

func (c *counter) totals() (up, down int64) {
	return c.up.Load(), c.down.Load()
}
