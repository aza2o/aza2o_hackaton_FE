Deno.serve(async (req) => {
  try {
    // POST만 허용
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ comment: null }),
        {
          status: 405,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    // 요청 JSON 읽기
    const body = await req.json();

    // 입력값 검증
    if (
      !Array.isArray(body.gapMinutes) ||
      typeof body.sleepDebtMin !== "number" ||
      !Array.isArray(body.shiftPattern)
    ) {
      return new Response(
        JSON.stringify({ comment: null }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    // Gemini API Key 가져오기
    const apiKey = Deno.env.get("GEMINI_API_KEY");

    if (!apiKey) {
      throw new Error("GEMINI_API_KEY is not configured");
    }

    // Gemini에 전달할 프롬프트
    const prompt = `당신은 교대근무자의 수면 패턴을 설명하는 보조 AI입니다.

제공된 데이터를 바탕으로 최근 수면 패턴의 특징을 한국어 2~3문장으로 설명하세요.

진단하거나 의학적 조언을 하지 마세요.
질환 여부를 판단하지 마세요.
치료나 약물에 대한 조언을 하지 마세요.

최근 14일 수면 데이터를 바탕으로 코멘트를 작성해주세요.

취침 격차(분):
${JSON.stringify(body.gapMinutes)}

수면 부채(분):
${body.sleepDebtMin}

근무 패턴:
${JSON.stringify(body.shiftPattern)}`;

    // Gemini API 호출 (표준 generateContent 엔드포인트 — 원래 코드가 쓰던
    // v1beta/interactions는 이 API 키 형식(AQ.접두사)으로 401을 반환해서
    // 표준 엔드포인트로 교체함, 2026-08-20)
    const response = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent",
      {
       method: "POST",
       headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
       }),
      },
    );

    // Gemini API 실패
    if (!response.ok) {
      const errorText = await response.text();

      throw new Error(
        `Gemini API error: ${response.status} ${errorText}`,
     );
    }

    // Gemini 응답 읽기
    const result = await response.json();

    // Gemini가 생성한 텍스트 추출
    const comment =
      result.candidates?.[0]?.content?.parts?.find((p: any) => p.text)?.text ?? null;
    if (!comment) {
      throw new Error("Gemini response did not contain comment");
    }

    // 성공
    return new Response(
      JSON.stringify({ comment }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );

  } catch (error) {
    console.error("report function error:", error);

    // 서버/Gemini 오류
    return new Response(
      JSON.stringify({ comment: null }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  }
});
