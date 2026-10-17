package client

import (
	"context"
	"errors"
	"net"
	"testing"
	"time"
)

type cancelledDialer struct{ started chan struct{} }

func (d cancelledDialer) DialContext(ctx context.Context, _, _ string) (net.Conn, error) {
	close(d.started)
	<-ctx.Done()
	return nil, ctx.Err()
}

func TestSessionCancellationInterruptsPendingDial(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	dialer := cancelledDialer{make(chan struct{})}
	done := make(chan error, 1)
	go func() {
		_, err := MakeSessionContext(ctx, RemoteConnConfig{NumConn: 1}, AuthInfo{}, dialer)
		done <- err
	}()
	select {
	case <-dialer.started:
	case <-time.After(time.Second):
		t.Fatal("dial did not start")
	}
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("unexpected error: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("cancel did not stop pending dial")
	}
}
