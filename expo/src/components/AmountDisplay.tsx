import React from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, { Easing, FadeIn, FadeOut, LinearTransition, withSpring } from 'react-native-reanimated';
import { useReducedMotion } from '@/hooks/useReducedMotion';
import { amountGlyphs } from '@/logic/glyphs';
import { roundedTextStyle } from '@/theme/fonts';
import { useTokens } from '@/theme/tokens';

/** Maps Swift `.spring(response: 0.34, dampingFraction: 0.72)`. */
const SPRING = { damping: 14.4, stiffness: 342, mass: 1 };

function GlyphEntering() {
  'worklet';
  return {
    initialValues: {
      opacity: 0,
      transform: [{ translateY: 40.5 }, { scale: 0.55 }]
    },
    animations: {
      opacity: withSpring(1, SPRING),
      transform: [{ translateY: withSpring(0, SPRING) }, { scale: withSpring(1, SPRING) }]
    }
  };
}

function GlyphExiting() {
  'worklet';
  return {
    initialValues: {
      opacity: 1,
      transform: [{ translateY: 0 }, { scale: 1 }]
    },
    animations: {
      opacity: withSpring(0, SPRING),
      transform: [{ translateY: withSpring(-40.5, SPRING) }, { scale: withSpring(0.55, SPRING) }]
    }
  };
}

export function AmountDisplay({ text }: { text: string }): React.JSX.Element {
  const tokens = useTokens();
  const reduced = useReducedMotion();
  const type = roundedTextStyle({
    fontSize: 76,
    fontWeight: '600',
    color: tokens.expenseForeground,
    fontVariant: ['tabular-nums']
  });
  const layout = reduced ? undefined : LinearTransition.springify().damping(14.4).stiffness(342);
  return (
    <View accessibilityLabel="Amount" style={styles.row}>
      {amountGlyphs(text).map(glyph => (
        <Animated.Text
          key={glyph.id}
          entering={reduced ? FadeIn.duration(200).easing(Easing.inOut(Easing.quad)) : GlyphEntering}
          exiting={reduced ? FadeOut.duration(200).easing(Easing.inOut(Easing.quad)) : GlyphExiting}
          layout={layout}
          numberOfLines={1}
          style={type}
        >
          {glyph.character}
        </Animated.Text>
      ))}
      <Animated.Text layout={layout} style={[type, styles.currency]}>$</Animated.Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { width: '100%', flexDirection: 'row', alignItems: 'baseline', justifyContent: 'center' },
  currency: { marginLeft: 9.12 }
});
