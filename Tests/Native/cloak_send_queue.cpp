// Exercise the real transport and core mutex with idle reads and failed writes.
#define USE_ASIO
#define ASIO_STANDALONE
#define OPENVPN_LOG(x) do {} while (false)
#include <openvpn/common/bigmutex.hpp>
#include <atomic>
#include <cassert>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
#include <iostream>
#include <stdexcept>
#include <openvpn/transport/ptlink.hpp>
using namespace openvpn;
using namespace openvpn::PluggableTransports;

struct FakeConnection : Connection {
    enum Mode { partial, zero, negative, oversized, throwing, blocked } mode;
    std::mutex mutex;
    std::condition_variable cv;
    bool entered = false, closed = false;
    bool blockRead = false, readEntered = false;
    std::function<void()> onBlockedWrite;
    std::vector<unsigned char> sent;
    explicit FakeConnection(Mode m) : mode(m) {}
    size_t send(const asio::const_buffer& b) override {
        std::unique_lock<std::mutex> lock(mutex);
        entered = true;
        cv.notify_all();
        if (mode == blocked) {
            if (onBlockedWrite) onBlockedWrite();
            cv.wait(lock, [&] { return closed; });
            // Read the buffer after stop to catch a premature release under ASan.
            assert(static_cast<const unsigned char*>(b.data())[2] == 1);
            return size_t(-1);
        }
        if (mode == zero) return 0;
        if (mode == negative) return size_t(-1);
        if (mode == oversized) return b.size() + 1;
        if (mode == throwing) throw std::runtime_error("write failed");
        size_t n = std::min(size_t(3), b.size());
        auto bytes = static_cast<const unsigned char*>(b.data());
        sent.insert(sent.end(), bytes, bytes+n);
        return n;
    }
    size_t receive(const asio::mutable_buffer&) override {
        std::unique_lock<std::mutex> lock(mutex);
        readEntered = true;
        cv.notify_all();
        if (blockRead) cv.wait(lock, [&] { return closed; });
        return size_t(-1);
    }
    void close() override { std::lock_guard<std::mutex> lock(mutex); closed = true; cv.notify_all(); }
    int native_handle() override { return -1; }
    int get_ret_out_int() override { return 0; }
};
struct Reader {
    int errors = 0, drained = 0;
    std::function<void()> onDrained;
    void pt_error_handler(const char*) { ++errors; }
    void pt_eof_handler() { assert(false); }
    bool pt_read_handler(BufferAllocated&) { return true; }
    void pt_write_queue_needs_send() { ++drained; if (onDrained) onDrained(); }
};
using Link = LinkImpl<Reader*>;
const Frame::Context frame(32, 2048, 32, 0, 8, 0);

bool sendPacket(Link& link, unsigned char value) {
    auto packet = frame.alloc();
    for (int i=0; i<16; ++i) packet.push_back(value);
    return link.send(packet);
}
void sends(FakeConnection::Mode mode) {
    asio::io_context io;
    Reader reader;
    SessionStats::Ptr stats = new SessionStats();
    RCPtr<FakeConnection> connection = new FakeConnection(mode);
    Link::Ptr link = new Link(io, &reader, connection, 64, 4, frame, stats);
    assert(sendPacket(*link, 42));
    assert(sendPacket(*link, 43));
    io.run();
    if (mode == FakeConnection::partial) {
        assert(link->send_queue_empty());
        assert(connection->sent.size() == 36);
        assert(connection->sent[0] == 0 && connection->sent[1] == 16);
        assert(connection->sent[18] == 0 && connection->sent[19] == 16);
        for (int i=2; i<18; ++i) assert(connection->sent[i] == 42);
        for (int i=20; i<36; ++i) assert(connection->sent[i] == 43);
        assert(stats->get_stat(SessionStats::BYTES_OUT) == 36);
        assert(reader.errors == 0 && reader.drained == 1);
    } else {
        assert(reader.errors == 1 && reader.drained == 0);
        assert(!sendPacket(*link, 44));
    }
}
void stopBlockedWriter(bool overflow) {
    asio::io_context io;
    Reader reader;
    RCPtr<FakeConnection> connection = new FakeConnection(FakeConnection::blocked);
    Link::Ptr link = new Link(io, &reader, connection, 2, 4, frame, new SessionStats());
    // Queue stop only once the writer has entered: it cannot run on the VPN
    // loop until a synchronous send returns, proving the original deadlock.
    bool commandExecuted = false;
    connection->onBlockedWrite = [&] { asio::post(io, [&] {
        commandExecuted = true;
        if (overflow) {
            assert(sendPacket(*link, 2));
            assert(!sendPacket(*link, 3));
            assert(reader.errors == 1);
        }
        link->stop();
        connection->close();
        link.reset();
    }); };
    asio::post(io, [&] { assert(sendPacket(*link, 1)); });
    io.run();
    assert(connection->entered && commandExecuted && reader.errors == (overflow ? 1 : 0));
}
// The real iOS macro takes OpenVPN's global mutex. Replacing it with an empty
// macro hid a deadlock: an idle Cloak_read held it until the server's next ping,
// preventing TUN reads, timers and user stop from running on the core loop.
void idleReadDoesNotBlockCore(bool sendBeforeStop) {
    asio::io_context io;
    Reader reader;
    RCPtr<FakeConnection> connection = new FakeConnection(FakeConnection::partial);
    connection->blockRead = true;
    Link::Ptr link = new Link(io, &reader, connection, 64, 4, frame, new SessionStats());
    link->start();
    {
        std::unique_lock<std::mutex> lock(connection->mutex);
        assert(connection->cv.wait_for(lock, std::chrono::seconds(2), [&] { return connection->readEntered; }));
    }
    std::atomic<bool> rescued{false};
    // Always release the blocked read, including on the broken implementation,
    // so a regression reports a failure rather than hanging the test runner.
    std::thread watchdog([&] {
        std::unique_lock<std::mutex> lock(connection->mutex);
        if (!connection->cv.wait_for(lock, std::chrono::seconds(1), [&] { return connection->closed; })) {
            rescued = true;
            lock.unlock();
            connection->close();
        }
    });
    auto stop = [&] {
        OPENVPN_ASYNC_HANDLER;
        link->stop();
        connection->close();
    };
    reader.onDrained = stop;
    asio::post(io, [&] {
        OPENVPN_ASYNC_HANDLER;
        if (sendBeforeStop) assert(sendPacket(*link, 42));
        else stop();
    });
    io.run();
    watchdog.join();
    if (rescued) throw std::runtime_error("idle Cloak receive blocked the core mutex (send/stop required a remote packet)");
    assert(reader.errors == 0);
    assert(reader.drained == (sendBeforeStop ? 1 : 0));
    assert(connection->sent.size() == (sendBeforeStop ? 18 : 0));
}
int main(int argc, char**) {
    idleReadDoesNotBlockCore(true);
    idleReadDoesNotBlockCore(false);
    if (argc > 1) {
        stopBlockedWriter(false);
        std::cout << "PASS: event loop remains responsive during a blocked write\n";
        return 0;
    }
    for (int i=0; i<100; ++i) {
        sends(FakeConnection::partial);
        sends(FakeConnection::zero);
        sends(FakeConnection::negative);
        sends(FakeConnection::oversized);
        sends(FakeConnection::throwing);
        stopBlockedWriter(false);
        stopBlockedWriter(true);
    }
    std::cout << "PASS: idle receive permits send and stop with the real core mutex; 700 native send cases (ordering/partial/error/stop/backpressure/lifetime)\n";
}
