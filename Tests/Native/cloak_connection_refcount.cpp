#include <openvpn/transport/client/pluggable/pt.hpp>

#include <atomic>
#include <cstdlib>
#include <iostream>
#include <thread>

using Connection = openvpn::PluggableTransports::Connection;

class ProbeConnection final : public Connection {
public:
    explicit ProbeConnection(std::atomic<int>& destroyed) : destroyed_(destroyed) {}
    ~ProbeConnection() override { ++destroyed_; }
    size_t send(const openvpn_io::const_buffer&) override { return 0; }
    size_t receive(const openvpn_io::mutable_buffer&) override { return 0; }
    void close() override {}
    int native_handle() override { return 7; }
    int get_ret_out_int() override { return 0; }

private:
    std::atomic<int>& destroyed_;
};

int main() {
    std::atomic<int> destroyed{0};
    {
        Connection::Ptr connection(new ProbeConnection(destroyed));
        Connection::Ptr sendOwner = connection;
        Connection::Ptr receiveOwner = connection;
        std::atomic<bool> start{false};

        // ptlink.hpp sends on the VPN thread while a receive worker releases
        // its captured Connection::Ptr. Each thread owns a different pointer;
        // only the pointed-to object's reference count is shared.
        auto copyAndRelease = [&start](const Connection::Ptr& owner) {
            while (!start.load(std::memory_order_acquire)) {}
            for (int i = 0; i < 20000; ++i) {
                Connection::Ptr temporary = owner;
                if (temporary->native_handle() != 7) std::abort();
            }
        };
        std::thread sender(copyAndRelease, std::cref(sendOwner));
        std::thread receiver(copyAndRelease, std::cref(receiveOwner));
        start.store(true, std::memory_order_release);
        sender.join();
        receiver.join();

        if (destroyed != 0 || connection->use_count() != 3) std::abort();
        sendOwner.reset();
        receiveOwner.reset();
        if (destroyed != 0 || connection->use_count() != 1) std::abort();
    }
    if (destroyed != 1) std::abort();
    std::cout << "PASS Connection: concurrent references and one final destruction\n";
}
