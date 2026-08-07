import { useId } from 'react';

/**
 * The Total Recall mark, inlined so it stays crisp at any size.
 *
 * Same design as Distribution/AppIcon.svg with two deliberate differences: the
 * board is scaled up to fill the tile, because there's no macOS shell margin to
 * reserve for a Dock shadow here, and the connector's finger dividers are
 * dropped because they land under a pixel at nav size. Keep in sync with
 * site/public/favicon.svg.
 *
 * The gradient and clip ids are per-instance — the mark renders more than once
 * per page, and duplicate ids would be invalid markup.
 */
export default function Logo({ size = 24 }: { size?: number }) {
  const uid = useId();
  const boardId = `tr-board-${uid}`;
  const clipId = `tr-clip-${uid}`;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 512 512"
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <linearGradient id={boardId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#6A93CE" />
          <stop offset="1" stopColor="#4E76B2" />
        </linearGradient>
        <clipPath id={clipId}>
          <rect x="56" y="104" width="400" height="304" rx="26" />
        </clipPath>
      </defs>

      <rect width="512" height="512" rx="112" fill="#12141A" />

      <g clipPath={`url(#${clipId})`}>
        <rect x="56" y="104" width="400" height="304" fill={`url(#${boardId})`} />
        <g fill="#33507E">
          <rect x="86" y="152" width="106" height="162" rx="14" />
          <rect x="203" y="152" width="106" height="162" rx="14" />
          <rect x="320" y="152" width="106" height="162" rx="14" />
        </g>
        <rect x="56" y="356" width="400" height="52" fill="#E0902F" />
        <rect x="236" y="356" width="40" height="52" fill="#5C84C0" />
      </g>
    </svg>
  );
}
