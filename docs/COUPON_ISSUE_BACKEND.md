# 쿠폰 발급 백엔드 (tas Phase 2) — 적용 대기 코드

> iOS 쿠폰 발급(`TASService.issueCoupon/cancelCoupon`)이 호출할 tas 백엔드 엔드포인트.
>
> **상태: tas에 PR로 올라가 있음(리뷰 대기).** 아래 코드는 그 PR의 내용이며, `membership-issue.ts`
> 패턴을 미러한 것이다. 이 문서는 계약·리뷰 포인트 참고용으로 남긴다.
> - tas PR **#156** — 쿠폰 발급/취소 엔드포인트 + 가드 (브랜치 `claude/coupon-issue-phase2`)
> - tas PR **#157** — 회원권 발급 가드(보관 상품 차단) — 쿠폰과 규칙 일치 (브랜치 `claude/membership-issue-guard`)
> - tas PR **#159** — 쿠폰 상품별 **'고객당 1장'(`oncePerCustomer`)** 설정 (#156 위 스택, **DB 마이그레이션 포함**)
> - 둘 다 **Draft**. tas는 머지 시 자동 배포되므로 **자동 머지 제외 + 사람 리뷰 후 머지**.

## 전제 (확인됨)
- DB 모델 `CustomerCoupon`은 **이미 tas prisma 스키마에 존재** → **마이그레이션 불필요**.
- `GET /api/coupons`는 이미 발급분(`coupons`)을 반환 → 조회는 그대로 동작.
- 없는 것은 **발급/취소 엔드포인트**뿐 → 아래 파일 2개만 추가하면 Phase 2(직접 발급) 완성.

## 계약
`POST /api/coupon-issue` (staff) — `{ customerId: number, productId: string }` → `{ id }`
`DELETE /api/coupon-issue` (staff) — `{ id }` → `{ ok: true }` (status→cancelled)

### 발급 가드 (쿠폰 특화 — 회원권엔 없는 규칙)
- **보관(archived) 상품 발급 차단** → 400
- **코드형(`code` 있음) 직접발급 차단** → 400 (코드 사용 흐름 전용, "직접발급 전용 = code 없음" 설계와 일치)
- iOS도 동일 규칙: 발급 대상 목록에서 보관·코드형 제외.
- **회원권도 동일 규칙 적용**(PR #157): 보관 상품 발급 차단. 회원권엔 코드형 개념이 없어 `code` 가드는 해당 없음.
  ⚠️ `membership-issue`는 운영 중 엔드포인트라 이 가드는 **라이브 동작 변경**(현재는 보관 상품도 발급 가능).
- (미적용) `Store.useCouponSystem`/`useMembershipSystem` 토글 체크·중복 발급 제한 — 넣으려면 쿠폰·회원권 양쪽 동시에 적용 권장.

## 추가할 파일 1 — `server/api/coupon-issue.ts`
```ts
import type {NextApiRequest, NextApiResponse} from 'next';

import {prisma} from '../db/prisma';
import {getApiSession, requireRole} from '../auth/api-session';

// 쿠폰 직접 발급/취소. (상품 CRUD는 ./coupons.ts) — 회원권 membership-issue 패턴 미러.
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
    const session = await getApiSession(req, res);

    if (req.method === 'POST') {
        if (!requireRole(session, 'staff', res)) return;

        const {customerId, productId} = req.body as {customerId?: unknown; productId?: unknown};
        if (typeof customerId !== 'number' || !Number.isInteger(customerId)) {
            return res.status(400).json({error: 'Invalid customerId'});
        }
        if (typeof productId !== 'string') {
            return res.status(400).json({error: 'Invalid productId'});
        }

        const customer = await prisma.customer.findUnique({
            where: {storeId_legacyId: {storeId: session.storeId, legacyId: customerId}},
            select: {id: true},
        });
        if (!customer) return res.status(404).json({error: 'Customer not found'});

        const product = await prisma.couponProduct.findFirst({
            where: {id: productId, storeId: session.storeId},
        });
        if (!product) return res.status(404).json({error: 'Product not found'});

        // 가드: 보관(archived) 상품은 발급 불가.
        if (product.status !== 'active') {
            return res.status(400).json({error: '보관된 쿠폰은 발급할 수 없습니다.'});
        }
        // 가드: 코드형(code 있음)은 코드 사용 흐름 전용 — 직접 발급 대상 아님.
        if (product.code) {
            return res.status(400).json({error: '코드형 쿠폰은 직접 발급 대상이 아닙니다.'});
        }

        const expiresAt = product.validDays != null
            ? new Date(Date.now() + product.validDays * 24 * 60 * 60 * 1000)
            : null;

        const created = await prisma.customerCoupon.create({
            data: {
                storeId: session.storeId,
                customerId: customer.id,
                productId: product.id,
                name: product.name,
                discountType: product.discountType,
                discountValue: product.discountValue,
                maxDiscount: product.maxDiscount,
                minOrderAmount: product.minOrderAmount,
                expiresAt,
                status: 'active',
            },
        });

        return res.status(200).json({id: created.id});
    }

    if (req.method === 'DELETE') {
        if (!requireRole(session, 'staff', res)) return;

        const {id} = req.body as {id?: unknown};
        if (typeof id !== 'string') return res.status(400).json({error: 'Invalid id'});

        const result = await prisma.customerCoupon.updateMany({
            where: {id, storeId: session.storeId},
            data: {status: 'cancelled'},
        });
        if (result.count === 0) return res.status(404).json({error: 'Not found'});
        return res.status(200).json({ok: true});
    }

    res.setHeader('Allow', ['POST', 'DELETE']);
    return res.status(405).end(`Method ${req.method} Not Allowed`);
}
```

## 추가할 파일 2 — `client/pages/api/coupon-issue.ts`
```ts
export {default} from '../../../server/api/coupon-issue';
```

## 적용 절차 (사용자)
1. 위 2개 파일을 tas에 추가(마이그레이션 없음).
2. **새 브랜치 + PR**로 올리고 리뷰. tas는 머지 시 자동 배포되므로 **자동 머지 제외**.
3. 머지 후 iOS 발급 UI가 동작(로그인 상태에서).

## iOS 쪽 (이미 이식 완료 — 이 저장소)
- `CustomerCoupon` 모델 + `CouponsResponse.coupons`
- `TASService.issueCoupon(customerId:productId:)` · `cancelCoupon(id:)` (게스트는 "로그인 후 이용" 차단)
- `CouponsView` 상품/발급 탭 — 발급 시트(고객+상품), 발급 내역 취소. 로그인 게이트.

## 후속(이번 범위 밖)
- **코드형 발급**(고객이 코드 입력) — `CouponProduct.code` 활용, 별도 흐름.
- **결제 자동 차감**(`PaymentMethod.coupon`, Phase 3) — 예약 결제 연동 + enum 확장, 회원권 Phase 3와 함께.
