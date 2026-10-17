import { animate } from "motion";

/**
 * SwiftUI's `.spring(response:dampingFraction:)`, as Motion physics. The app's curves are
 * written that way, so the site borrows the exact values instead of eyeballing them:
 * stiffness = (2π / response)², damping = 4π · dampingFraction / response, mass 1.
 */
export function swiftSpring(response: number, dampingFraction: number) {
  return {
    type: "spring" as const,
    stiffness: (2 * Math.PI / response) ** 2,
    damping: (4 * Math.PI * dampingFraction) / response,
    mass: 1,
  };
}

/** The curves `BrandMark.swift`, `SplashView.swift` and `AmountDisplay.swift` use. */
export const springs = {
  /** Splash: the coin settling to full size. */
  grow: swiftSpring(0.4, 0.82),
  /** Splash: the cut landing. */
  cut: swiftSpring(0.4, 0.68),
  /** Loader: halves meeting. */
  join: swiftSpring(0.5, 0.7),
  /** Settled coin: halves meeting. Livelier than `join`, because `Coin.close` stops them
   *  at the joined position instead of letting the overshoot carry them through it. */
  settle: swiftSpring(0.5, 0.55),
  /** Settled coin: the whole coin taking the impact of the halves meeting. */
  wobble: swiftSpring(0.42, 0.42),
  /** Loader: halves parting again. */
  part: swiftSpring(0.5, 0.62),
  /** Amount digits. */
  amount: swiftSpring(0.34, 0.72),
  /** `.snappy`: layout that should land without overshoot. */
  snappy: swiftSpring(0.3, 0.86),
};

/**
 * Drives a coin's two halves. `separation` 0 is one whole coin, 1 is the mark. Each half
 * sits 40 units off centre vertically and half the gap horizontally on the 256 grid,
 * mirroring `SplittySymbol`.
 */
export class Coin {
  readonly el: SVGSVGElement;
  private a: SVGGElement;
  private b: SVGGElement;
  private halfGap: number;
  separation: number;

  constructor(el: SVGSVGElement) {
    this.el = el;
    this.a = el.querySelector<SVGGElement>("[data-half=a]")!;
    this.b = el.querySelector<SVGGElement>("[data-half=b]")!;
    this.halfGap = Number(el.dataset.halfGap ?? 9);
    this.separation = Number(el.dataset.separation ?? 1);
    this.render(this.separation);
  }

  render(separation: number) {
    this.separation = separation;
    const dx = this.halfGap * separation;
    const dy = 40 * separation;
    this.a.setAttribute("transform", `translate(${-dx} ${-dy})`);
    this.b.setAttribute("transform", `translate(${dx} ${dy})`);
  }

  /**
   * Brings the halves together and seats them: they arrive on a lively spring but stop dead
   * at the joined position, never sliding past each other. The impact goes into the whole
   * coin instead, as a short springy wobble in scale.
   */
  close(transition = springs.settle) {
    let wobbling: { stop(): void } | undefined;
    const closing = animate(this.separation, 0, {
      ...transition,
      onUpdate: (value) => {
        if (wobbling || value > 0) {
          if (!wobbling) this.render(value);
          return;
        }
        this.render(0);
        closing.stop();
        wobbling = wobble(this.el, 1.2, springs.wobble);
      },
    });
    return {
      stop() {
        closing.stop();
        wobbling?.stop();
      },
    };
  }

  to(separation: number, transition = springs.cut) {
    return animate(this.separation, separation, {
      ...transition,
      onUpdate: (value) => this.render(value),
    });
  }
}

/**
 * Kicks an element's scale with a velocity and lets a spring bring it back to 1: a bump
 * that overshoots and settles. Integrated here because a spring from 1 to 1 is one Motion
 * considers finished before it starts.
 */
export function wobble(el: HTMLElement | SVGElement, velocity: number, spring: { stiffness: number; damping: number }) {
  let x = 0;
  let v = velocity;
  let last = performance.now();
  let frame = 0;
  const step = (now: number) => {
    // Fixed small steps keep the integration stable when a frame runs long.
    for (let t = Math.min((now - last) / 1000, 0.05); t > 0; t -= 1 / 240) {
      const dt = Math.min(t, 1 / 240);
      v += (-spring.stiffness * x - spring.damping * v) * dt;
      x += v * dt;
    }
    last = now;
    if (Math.abs(x) < 0.0005 && Math.abs(v) < 0.005) {
      el.style.transform = "";
      return;
    }
    el.style.transform = `scale(${1 + x})`;
    frame = requestAnimationFrame(step);
  };
  frame = requestAnimationFrame(step);
  return {
    stop() {
      cancelAnimationFrame(frame);
      el.style.transform = "";
    },
  };
}

/** Counts a number to its target on the app's amount spring, writing formatted text. */
export function countTo(
  el: Element,
  from: number,
  to: number,
  format: (value: number) => string,
  transition = springs.amount,
) {
  return animate(from, to, {
    ...transition,
    onUpdate: (value) => {
      el.textContent = format(value);
    },
  });
}

export const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
