package main

import (
	"context"
	"io"
	"net"
	"testing"
	"time"
	"unsafe"

	"github.com/cbeuw/Cloak/internal/client"
	"github.com/cbeuw/Cloak/internal/multiplex"
	"github.com/cbeuw/connutil"
)

type pipeDialer struct{ net.Conn }

func (d pipeDialer) DialContext(context.Context, string, string) (net.Conn, error) {
	return d.Conn, nil
}

type plainTransport struct{ net.Conn }

func (p *plainTransport) Handshake(conn net.Conn, _ client.AuthInfo) ([32]byte, error) {
	p.Conn = conn
	return [32]byte{}, nil
}

func TestRouteCloakRoundTripAndClose(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	wire, remote := net.Pipe()
	defer remote.Close()
	obfuscator, err := multiplex.MakeObfuscator(multiplex.EncryptionMethodPlain, [32]byte{})
	if err != nil {
		t.Fatal(err)
	}
	server := multiplex.MakeSession(1, multiplex.SessionConfig{Obfuscator: obfuscator})
	server.AddConnection(remote)
	local, peer := connutil.LimitedAsyncPipe(10 * 1024)
	connection := &cloakConnection{Conn: local, cancel: cancel}
	id := registerTestConnection(connection)
	defer Cloak_close_connection(id)
	done := make(chan struct{})
	go func() {
		defer close(done)
		routeCloak(connection, peer, time.Second, func() (*multiplex.Session, error) {
			return client.MakeSessionContext(ctx, client.RemoteConnConfig{
				NumConn: 1, TransportMaker: func() client.Transport { return &plainTransport{} },
			}, client.AuthInfo{SessionId: 1, EncryptionMethod: multiplex.EncryptionMethodPlain}, pipeDialer{wire})
		})
	}()
	serverDone := make(chan error, 1)
	go func() {
		stream, err := server.Accept()
		if err == nil {
			buf := make([]byte, 4)
			_, err = io.ReadFull(stream, buf)
			if err == nil {
				_, err = stream.Write(buf)
			}
		}
		serverDone <- err
	}()
	message := []byte("ping")
	if n := Cloak_write(id, unsafe.Pointer(&message[0]), 4); n != 4 {
		t.Fatalf("write returned %d", n)
	}
	local.SetReadDeadline(time.Now().Add(2 * time.Second))
	reply := make([]byte, 4)
	if n := Cloak_read(id, unsafe.Pointer(&reply[0]), 4); n != 4 || string(reply) != "ping" {
		t.Fatalf("round trip returned %d bytes: %q", n, reply)
	}
	Cloak_close_connection(id)
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("route worker survived close")
	}
	select {
	case err := <-serverDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("server worker survived close")
	}
}
