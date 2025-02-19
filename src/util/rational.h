#pragma once

#include <cstdint>

namespace vkad {

class Rational {
public:
   Rational(int64_t numerator, int64_t denominator);

   Rational operator+(const Rational &other) const;
   Rational operator-(const Rational &other) const;
   Rational operator*(const Rational &other) const;
   Rational operator/(const Rational &other) const;

   int64_t numerator() const {
      return numerator_;
   }

   int64_t denominator() const {
      return denominator_;
   }

private:
   void reduce();

   int64_t numerator_;
   int64_t denominator_;
};

} // namespace vkad
