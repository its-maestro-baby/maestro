import type { SVGProps } from "react";

interface OpenCodeIconProps extends SVGProps<SVGSVGElement> {
  size?: number;
}

/**
 * OpenCode brand icon component.
 * Downloaded from https://dashboardicons.com/icons/opencode
 * Accepts same props as Lucide icons for consistency.
 */
export function OpenCodeIcon({ size = 24, className = "", ...props }: OpenCodeIconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      aria-label="OpenCode"
      {...props}
    >
      <title>OpenCode</title>
      <path
        d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1.5 15.5h-2v-7h2v7zm5 0h-2v-7h2v7zm-2.5-9.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z"
        fill="currentColor"
      />
    </svg>
  );
}
