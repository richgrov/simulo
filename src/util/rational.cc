#include "util/rational.h"

#include <numeric>
#include <stdexcept>

using namespace simulo;

Rational::Rational(int64_t numerator, int64_t denominator)
    : numerator_(numerator), denominator_(denominator) {
   if (denominator_ == 0) {
      throw std::invalid_argument("denominator is zero");
   }

   reduce();
}

void Rational::reduce() {
   int64_t gcd = std::gcd(numerator_, denominator_);
   numerator_ /= gcd;
   denominator_ /= gcd;

   if (denominator_ < 0) {
      numerator_ = -numerator_;
      denominator_ = -denominator_;
   }
}

Rational Rational::operator+(const Rational &other) const {
   return Rational(
       numerator_ * other.denominator_ + other.numerator_ * denominator_,
       denominator_ * other.denominator_
   );
}

Rational Rational::operator-(const Rational &other) const {
   return Rational(
       numerator_ * other.denominator_ - other.numerator_ * denominator_,
       denominator_ * other.denominator_
   );
}

Rational Rational::operator*(const Rational &other) const {
   return Rational(numerator_ * other.numerator_, denominator_ * other.denominator_);
}

Rational Rational::operator/(const Rational &other) const {
   if (other.numerator_ == 0) {
      throw std::invalid_argument("division by zero");
   }

   return Rational(numerator_ * other.denominator_, denominator_ * other.numerator_);
}
