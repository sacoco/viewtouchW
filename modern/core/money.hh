#pragma once

// Money as a signed count of cents. Replaces the legacy mix of int cents and
// Flt rates; all arithmetic is integral and rounding is explicit.

#include <compare>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <string>

namespace vt {

class Money {
public:
    constexpr Money() = default;
    static constexpr Money fromCents(std::int64_t cents) { return Money(cents); }

    constexpr std::int64_t cents() const { return cents_; }

    constexpr Money operator+(Money o) const { return Money(cents_ + o.cents_); }
    constexpr Money operator-(Money o) const { return Money(cents_ - o.cents_); }
    constexpr Money operator-() const { return Money(-cents_); }
    constexpr Money operator*(std::int64_t qty) const { return Money(cents_ * qty); }
    constexpr Money &operator+=(Money o) { cents_ += o.cents_; return *this; }
    constexpr Money &operator-=(Money o) { cents_ -= o.cents_; return *this; }

    constexpr auto operator<=>(const Money &) const = default;

    // this * numerator / denominator, rounded half away from zero to the
    // nearest cent (the legacy FltToPrice rule), in exact integer math.
    constexpr Money scaled(std::int64_t numerator, std::int64_t denominator) const
    {
        std::int64_t num = 0;
#if defined(__GNUC__) || defined(__clang__)
        const bool overflowed = __builtin_mul_overflow(cents_, numerator, &num);
#else
        // MSVC has no constexpr-friendly overflow-checked multiply intrinsic
        // (unlike GCC/Clang's builtin above). Detect the overflow by
        // magnitude first — multiplying before knowing it's safe would
        // itself be undefined behavior — then multiply only once proven
        // safe. `ub > limit / ua` (integer division) is exact: no false
        // positives or negatives, for every int64 input including INT64_MIN.
        const std::uint64_t ua = cents_ < 0 ? 0u - std::uint64_t(cents_) : std::uint64_t(cents_);
        const std::uint64_t ub = numerator < 0 ? 0u - std::uint64_t(numerator) : std::uint64_t(numerator);
        const std::uint64_t limit = (cents_ < 0) != (numerator < 0)
            ? std::uint64_t(std::numeric_limits<std::int64_t>::max()) + 1   // |INT64_MIN|
            : std::uint64_t(std::numeric_limits<std::int64_t>::max());
        const bool overflowed = ua != 0 && ub > limit / ua;
        if (!overflowed)
            num = cents_ * numerator;
#endif
        if (overflowed) {
            // Past what 64 bits hold (only an absurd amount: a damaged
            // record): near enough in long double, held to what fits,
            // never undefined.
            const long double v = (long double)cents_ * numerator / denominator;
            constexpr long double top = 9.2e18L;
            return Money(std::int64_t(v > top ? top : v < -top ? -top : v));
        }
        const std::int64_t q = num / denominator;
        const std::int64_t r = num % denominator;
        const std::int64_t twice = (r < 0 ? -r : r) * 2;
        if (twice >= (denominator < 0 ? -denominator : denominator))
            return Money(num < 0 ? q - 1 : q + 1);
        return Money(q);
    }

    // Percentage in basis points (1 bp = 0.01%), e.g. 10% = 1000.
    constexpr Money percent(std::int64_t basisPoints) const { return scaled(basisPoints, 10000); }

    // Rate in parts per million, e.g. 9.975% = 99750. Tax rates use this so
    // three-decimal rates (Quebec QST) are exact.
    constexpr Money ppm(std::int64_t partsPerMillion) const { return scaled(partsPerMillion, 1000000); }

    // "12.34", "-0.05" - the stable, machine-readable form (JSON, CSV):
    // always a plain decimal point, never grouped. Never changes shape;
    // other code parses this back.
    std::string toString() const
    {
        const std::int64_t a = cents_ < 0 ? -cents_ : cents_;
        std::string frac = std::to_string(a % 100);
        if (frac.size() < 2) frac.insert(0, "0");
        return (cents_ < 0 ? "-" : "") + std::to_string(a / 100) + "." + frac;
    }

    // For a person to read: a chosen decimal point, a thousands separator
    // (empty: none shown), and how many digits after the point - 0 for a
    // currency with no sub-unit in everyday use (the Colombian or Chilean
    // peso, the yen...). "1,234.56", "1.234,56", "1.234" (places 0).
    // Still exact underneath: this only rounds and punctuates what's shown.
    std::string format(const std::string &decimalPoint = ".", const std::string &groupSeparator = {},
                        int places = 2) const
    {
        const int shown = places < 0 ? 0 : places > 2 ? 2 : places;
        const std::int64_t placeDigits = shown == 0 ? 1 : shown == 1 ? 10 : 100;
        const std::int64_t divisor = 100 / placeDigits;    // raw cents per smallest shown digit
        const std::int64_t a = cents_ < 0 ? -cents_ : cents_;
        const std::int64_t units = (a + divisor / 2) / divisor;   // rounded, half away from zero
        std::string whole = std::to_string(units / placeDigits);
        if (!groupSeparator.empty())
            for (int pos = int(whole.size()) - 3; pos > 0; pos -= 3)
                whole.insert(std::size_t(pos), groupSeparator);
        std::string out = (cents_ < 0 && units != 0 ? "-" : "") + whole;
        if (shown > 0) {
            std::string frac = std::to_string(units % placeDigits);
            while (int(frac.size()) < shown)
                frac.insert(0, "0");
            out += decimalPoint + frac;
        }
        return out;
    }

private:
    constexpr explicit Money(std::int64_t cents) : cents_(cents) {}
    std::int64_t cents_ = 0;
};

} // namespace vt
