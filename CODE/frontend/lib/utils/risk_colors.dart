import 'package:flutter/material.dart';

import '../data/disease_kb.dart';
import '../services/risk_engine.dart';

/// The severity scale, shared by the weather screen, the hotspot map, the
/// result screen and the officer dashboard so "high risk" looks the same
/// everywhere in the product.
///
/// WHY THIS IS A SEQUENTIAL RAMP AND NOT GREEN/AMBER/ORANGE/RED
///
/// The obvious palette for risk is a traffic light. It was measured and it
/// fails: amber, orange and red are adjacent hues, and under deuteranopia or
/// protanopia neighbouring pairs collapsed to a perceptual distance of
/// 0.7-2.6 (OKLab dE x100, against a floor of 8). A red-green colourblind
/// officer - roughly 1 in 12 men - could not have told a moderate district
/// from a severe one. Text labels do not rescue a separation that low.
///
/// Severity is an *ordered* scale, so it takes the color treatment ordered
/// data takes: one hue, light to dark. Lightness carries the ordering, which
/// survives every form of colour vision deficiency and greyscale printing.
/// Measured steps: L 0.788 / 0.682 / 0.573 / 0.439, strictly decreasing.
///
/// Green is kept out of the ramp and reserved for a genuinely different
/// state - healthy, no disease found - so "green means fine" still holds.
///
/// The palest step sits at 2.0:1 against white, below the 3:1 mark, so every
/// use site pairs it with a visible text label. Never ship these as colour
/// alone.
class RiskColors {
  RiskColors._();

  /// Not a ramp step - a separate state meaning "no disease detected".
  static const Color healthy = Color(0xFF2E7D32);

  // Sequential severity ramp, light to dark.
  static const Color low = Color(0xFFF0A868);
  static const Color moderate = Color(0xFFDE7B3C);
  static const Color high = Color(0xFFC2501C);
  static const Color severe = Color(0xFF8C2F0D);

  static const Color unknown = Color(0xFF9E9E9E);

  /// Ink that stays readable on top of [surfaceFor] tints, and reads as the
  /// same family as the ramp. The palest ramp steps are too light to use as
  /// text, so label colour is taken from here instead.
  static const Color onTint = Color(0xFF7A2A0C);

  static Color forBand(RiskBand band) => switch (band) {
    RiskBand.low => low,
    RiskBand.moderate => moderate,
    RiskBand.high => high,
    RiskBand.severe => severe,
  };

  static Color forThreat(ThreatLevel t) => switch (t) {
    ThreatLevel.none => healthy,
    ThreatLevel.low => low,
    ThreatLevel.moderate => moderate,
    ThreatLevel.high => high,
    ThreatLevel.critical => severe,
  };

  /// Ramp for a 0-100 score, used by the map and the dashboard bars.
  static Color forScore(double score) {
    if (score >= 70) return severe;
    if (score >= 45) return high;
    if (score >= 20) return moderate;
    return low;
  }

  /// Text colour to sit on a [surfaceFor] tint of [c].
  ///
  /// The two palest ramp steps cannot carry text at an accessible contrast,
  /// so they borrow the darker [onTint] ink rather than being used directly.
  static Color inkOn(Color c) {
    if (c == low || c == moderate) return onTint;
    return c;
  }

  /// Tinted background that keeps text at an accessible contrast ratio.
  static Color surfaceFor(Color c) => Color.alphaBlend(
    c.withValues(alpha: 0.12),
    Colors.white,
  );
}
