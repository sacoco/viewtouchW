#include <catch2/catch_test_macros.hpp>

#include "core/money.hh"

using vt::Money;

TEST_CASE("Money arithmetic", "[money]")
{
    const Money a = Money::fromCents(1250);
    const Money b = Money::fromCents(275);

    CHECK((a + b).cents() == 1525);
    CHECK((a - b).cents() == 975);
    CHECK((b * 3).cents() == 825);
    CHECK((-a).cents() == -1250);
    CHECK(b < a);
}

TEST_CASE("Money percent rounds half away from zero", "[money]")
{
    // 8.25% of $10.00 = 82.5c -> 83c
    CHECK(Money::fromCents(1000).percent(825).cents() == 83);
    // 8.25% of $9.99 = 82.4175c -> 82c
    CHECK(Money::fromCents(999).percent(825).cents() == 82);
    // negative (refund) mirrors positive
    CHECK(Money::fromCents(-1000).percent(825).cents() == -83);
    CHECK(Money::fromCents(0).percent(825).cents() == 0);
}

TEST_CASE("Money formats as decimal string", "[money]")
{
    CHECK(Money::fromCents(1234).toString() == "12.34");
    CHECK(Money::fromCents(5).toString() == "0.05");
    CHECK(Money::fromCents(-5).toString() == "-0.05");
    CHECK(Money::fromCents(100000).toString() == "1000.00");
}

TEST_CASE("Money formats for a person to read, punctuated and rounded as chosen", "[money]")
{
    // The default - unpunctuated, 2 places - is exactly toString().
    CHECK(Money::fromCents(123456).format() == "1234.56");
    // Decimal comma, thousands point - most of Latin America and Europe.
    CHECK(Money::fromCents(123456).format(",", ".") == "1.234,56");
    CHECK(Money::fromCents(1234567890).format(",", ".") == "12.345.678,90");
    // Decimal point, thousands comma - the US and a few others.
    CHECK(Money::fromCents(123456).format(".", ",") == "1,234.56");
    // No sub-unit at all - the Colombian or Chilean peso, the yen: rounds
    // to the nearest whole unit, no point shown.
    CHECK(Money::fromCents(123456).format(",", ".", 0) == "1.235");   // 1234.56 -> 1235
    CHECK(Money::fromCents(123450).format(",", ".", 0) == "1.235");   // a tie (.50): away from zero, rounds up
    CHECK(Money::fromCents(123449).format(",", ".", 0) == "1.234");   // .49 rounds down
    CHECK(Money::fromCents(50).format(",", ".", 0) == "1");           // 0.50 rounds up to 1
    CHECK(Money::fromCents(49).format(",", ".", 0) == "0");
    // One decimal place.
    CHECK(Money::fromCents(123456).format(",", ".", 1) == "1.234,6");
    // Negative amounts, and a negative that rounds to zero shows no sign.
    CHECK(Money::fromCents(-123456).format(",", ".") == "-1.234,56");
    CHECK(Money::fromCents(-4).format(",", ".", 0) == "0");
    // Small amounts: no grouping separator appears below a thousand.
    CHECK(Money::fromCents(999).format(",", ".") == "9,99");
    CHECK(Money::fromCents(0).format(",", ".") == "0,00");
}

TEST_CASE("Money: a percent of an absurd amount is held to what fits, never undefined", "[money]")
{
    // 9.2e18 cents times 15.25% overflowed 64 bits in the middle (a damaged record).
    const Money huge = Money::fromCents(-9'200'000'000'000'000'000);
    const Money part = huge.percent(1525);
    CHECK(part.cents() < 0);
    CHECK(part.cents() > -9'200'000'000'000'000'000);
    CHECK(Money::fromCents(9'000'000'000'000'000'000).ppm(1'000'000).cents() > 8'000'000'000'000'000'000);
    // Everyday amounts: exactly as before.
    CHECK(Money::fromCents(1250).percent(825).cents() == 103);
    CHECK(Money::fromCents(-1250).percent(825).cents() == -103);
}
