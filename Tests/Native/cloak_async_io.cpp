#define USE_ASIO
#define ASIO_STANDALONE
#define OPENVPN_ASYNC_HANDLER
#define OPENVPN_LOG(x) do {} while (false)
#include <cassert>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <iostream>
#include <openvpn/transport/ptlink.hpp>
using namespace openvpn;
using namespace openvpn::PluggableTransports;

struct FakeConnection : Connection {
    enum Mode { partial, zero, negative, oversized, blocked } mode;
    std::mutex mutex;
    std::condition_variable cv;
    bool entered = false, closed = false;
    std::vector<unsigned char> sent;
    explicit FakeConnection(Mode m) : mode(m) {}
    size_t send(const asio::const_buffer& b) override {
        std::unique_lock<std::mutex> lock(mutex);
        entered = true;
        cv.notify_all();
        if (mode == blocked) { cv.wait(lock, [&] { return closed; }); return size_t(-1); }
        if (mode == zero) return 0;
        if (mode == negative) return size_t(-1);
        if (mode == oversized) return b.size() + 1;
        size_t n = std::min(size_t(3), b.size());
        auto bytes = static_cast<const unsigned char*>(b.data());
        sent.insert(sent.end(), bytes, bytes+n);
        return n;
    }
    size_t receive(const asio::mutable_buffer& b) override {
        if (mode == zero) return 0;
        return size_t(-1);
    }
    void close() override { std::lock_guard<std::mutex> lock(mutex); closed = true; cv.notify_all(); }
    int native_handle() override { return -1; }
    int get_ret_out_int() override { return 0; }
};
struct Reader {
    int errors = 0, eof = 0, drained = 0;
    void pt_error_handler(const char*) { ++errors; }
    void pt_eof_handler() { ++eof; }
    bool pt_read_handler(BufferAllocated&) { return true; }
    void pt_write_queue_needs_send() { ++drained; }
};
using Link = LinkImpl<Reader*>;
const Frame::Context frame(32, 2048, 32, 0, 8, 0);

void sendPacket(Link& link, unsigned char value) {
    auto packet = frame.alloc();
    for (int i=0; i<16; ++i) packet.push_back(value);
    assert(link.send(packet));
}
void sends(FakeConnection::Mode mode) {
    asio::io_context io;
    Reader reader;
    RCPtr<FakeConnection> connection = new FakeConnection(mode);
    Link::Ptr link = new Link(io, &reader, connection, 64, 4, frame, new SessionStats());
    sendPacket(*link, 42);
    sendPacket(*link, 43);
    io.run();
    if (mode == FakeConnection::partial) {
        assert(link->send_queue_empty());
        assert(connection->sent.size() == 36);
        for (int i=2; i<18; ++i) assert(connection->sent[i] == 42);
        for (int i=20; i<36; ++i) assert(connection->sent[i] == 43);
        assert(reader.errors == 0 && reader.drained == 1);
    } else assert(reader.errors == 1);
}
void stopBlockedWriter() {
    asio::io_context io;
    Reader reader;
    RCPtr<FakeConnection> connection = new FakeConnection(FakeConnection::blocked);
    Link::Ptr link = new Link(io, &reader, connection, 64, 4, frame, new SessionStats());
    sendPacket(*link, 1);
    {
        std::unique_lock<std::mutex> lock(connection->mutex);
        assert(connection->cv.wait_for(lock, std::chrono::seconds(2), [&] { return connection->entered; }));
    }
    bool commandExecuted = false;
    asio::post(io, [&] {
        commandExecuted = true;
        link->stop();
        connection->close();
        link.reset(); // completion must retain its buffer until the writer returns
    });
    io.run();
    assert(commandExecuted && reader.errors == 0);
}
void receives(FakeConnection::Mode mode) {
    asio::io_context io;
    Reader reader;
    RCPtr<FakeConnection> connection = new FakeConnection(mode);
    Link::Ptr link = new Link(io, &reader, connection, 64, 4, frame, new SessionStats());
    link->start();
    io.run();
    if (mode == FakeConnection::zero) assert(reader.eof == 1);
    else assert(reader.errors == 1);
}
int main() {
    for (int i=0; i<100; ++i) {
        sends(FakeConnection::partial);
        sends(FakeConnection::zero);
        sends(FakeConnection::negative);
        sends(FakeConnection::oversized);
        stopBlockedWriter();
        receives(FakeConnection::zero);
        receives(FakeConnection::negative);
    }
    std::cout << "PASS: 700 native async I/O cases (partial/error/EOF/cancel/lifetime)\n";
}
