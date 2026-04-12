#!/bin/bash

##############################################
# 여러 사용자를 생성하는 Wrapper 스크립트
#
# 사용법:
#   ./create_users.sh              # 기본 사용자 목록으로 생성
#   ./create_users.sh 5            # 5명의 사용자 생성
#   ./create_users.sh custom       # 커스텀 모드 (사용자 정의 데이터)
##############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALL_SCRIPT="${SCRIPT_DIR}/call-user.sh"

# call.sh가 실행 가능한지 확인
if [ ! -x "$CALL_SCRIPT" ]; then
    chmod +x "$CALL_SCRIPT"
fi

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 기본 사용자 데이터 배열
declare -a DEFAULT_USERS=(
    "홍길동:hong@example.com"
    "김철수:kim@example.com"
    "이영희:lee@example.com"
    "박민수:park@example.com"
    "최지훈:choi@example.com"
    "정수연:jung@example.com"
    "강민지:kang@example.com"
    "윤서준:yoon@example.com"
    "조은지:jo@example.com"
    "임도현:lim@example.com"
)

##############################################
# 함수: 사용자 생성
##############################################
create_user() {
    local name=$1
    local email=$2
    local index=$3

    echo -e "${BLUE}[$index] 사용자 생성 중...${NC}"
    echo -e "  이름: ${YELLOW}$name${NC}, 이메일: ${YELLOW}$email${NC}"

    if bash "$CALL_SCRIPT" "$name" "$email"; then
        echo -e "${GREEN}  생성 완료${NC}\n"
        return 0
    else
        echo -e "${RED}  생성 실패${NC}\n"
        return 1
    fi
}

##############################################
# 함수: 기본 사용자 목록으로 생성
##############################################
create_default_users() {
    local count=${1:-${#DEFAULT_USERS[@]}}
    local success=0
    local failed=0

    echo -e "${GREEN}==================================${NC}"
    echo -e "${GREEN}기본 사용자 생성 시작 (${count}명)${NC}"
    echo -e "${GREEN}==================================${NC}\n"

    for ((i=0; i<$count && i<${#DEFAULT_USERS[@]}; i++)); do
        IFS=':' read -r name email <<< "${DEFAULT_USERS[$i]}"

        if create_user "$name" "$email" $((i+1)); then
            ((success++))
        else
            ((failed++))
        fi

        # API 호출 간 딜레이 (너무 빠른 연속 호출 방지)
        sleep 0.5
    done

    echo -e "${GREEN}==================================${NC}"
    echo -e "${GREEN}생성 완료: ${success}명${NC}"
    if [ $failed -gt 0 ]; then
        echo -e "${RED}생성 실패: ${failed}명${NC}"
    fi
    echo -e "${GREEN}==================================${NC}"
}

##############################################
# 함수: 랜덤 사용자 생성
##############################################
create_random_users() {
    local count=$1
    local success=0
    local failed=0

    # 한글 성씨와 이름
    local surnames=("김" "이" "박" "최" "정" "강" "조" "윤" "장" "임" "한" "오" "서" "신" "권" "황" "안" "송" "류" "전")
    local names=("민준" "서연" "지훈" "서준" "하준" "지우" "수빈" "도윤" "예준" "시우" "유진" "은서" "민서" "하은" "채원")

    echo -e "${GREEN}==================================${NC}"
    echo -e "${GREEN}랜덤 사용자 생성 시작 (${count}명)${NC}"
    echo -e "${GREEN}==================================${NC}\n"

    for ((i=1; i<=count; i++)); do
        # 랜덤 이름 생성
        local surname=${surnames[$RANDOM % ${#surnames[@]}]}
        local name=${names[$RANDOM % ${#names[@]}]}
        local full_name="${surname}${name}"

        # 랜덤 이메일 생성
        local email="user${i}_${RANDOM}@example.com"

        if create_user "$full_name" "$email" $i; then
            ((success++))
        else
            ((failed++))
        fi

        sleep 0.5
    done

    echo -e "${GREEN}==================================${NC}"
    echo -e "${GREEN}생성 완료: ${success}명${NC}"
    if [ $failed -gt 0 ]; then
        echo -e "${RED}생성 실패: ${failed}명${NC}"
    fi
    echo -e "${GREEN}==================================${NC}"
}

##############################################
# 함수: 커스텀 사용자 생성 (대화형)
##############################################
create_custom_users() {
    echo -e "${YELLOW}==================================${NC}"
    echo -e "${YELLOW}커스텀 사용자 생성 모드${NC}"
    echo -e "${YELLOW}==================================${NC}\n"

    local continue="y"
    local index=1

    while [[ $continue == "y" || $continue == "Y" ]]; do
        echo -e "${BLUE}[$index] 사용자 정보 입력${NC}"

        read -p "이름: " name
        if [ -z "$name" ]; then
            echo -e "${RED}이름을 입력해주세요.${NC}"
            continue
        fi

        read -p "이메일: " email
        if [ -z "$email" ]; then
            echo -e "${RED}이메일을 입력해주세요.${NC}"
            continue
        fi

        create_user "$name" "$email" $index
        ((index++))

        read -p "계속 추가하시겠습니까? (y/n): " continue
        echo ""
    done

    echo -e "${GREEN}총 $((index-1))명의 사용자 생성을 시도했습니다.${NC}"
}

##############################################
# 함수: 도움말 출력
##############################################
show_help() {
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  (없음)          기본 사용자 목록 전체 생성 (${#DEFAULT_USERS[@]}명)"
    echo "  <숫자>          지정된 수만큼 기본 사용자 생성"
    echo "  random <숫자>   지정된 수만큼 랜덤 사용자 생성"
    echo "  custom          대화형 모드로 사용자 생성"
    echo "  help            이 도움말 표시"
    echo ""
    echo "예제:"
    echo "  $0              # 기본 사용자 전체 생성"
    echo "  $0 5            # 기본 사용자 5명 생성"
    echo "  $0 random 10    # 랜덤 사용자 10명 생성"
    echo "  $0 custom       # 대화형 모드"
}

##############################################
# 메인 로직
##############################################

# 서버가 실행 중인지 확인
echo -e "${YELLOW}서버 연결 확인 중...${NC}"
if ! curl -s -f http://localhost:8080/actuator/health > /dev/null 2>&1; then
    echo -e "${RED}서버에 연결할 수 없습니다.${NC}"
    echo -e "${RED}  localhost:8080에서 애플리케이션이 실행 중인지 확인해주세요.${NC}"
    exit 1
fi
echo -e "${GREEN}서버 연결 확인 완료${NC}\n"

# 인자 파싱
case "${1:-default}" in
    help|--help|-h)
        show_help
        ;;
    custom)
        create_custom_users
        ;;
    random)
        count=${2:-10}
        if ! [[ "$count" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}오류: 숫자를 입력해주세요.${NC}"
            show_help
            exit 1
        fi
        create_random_users $count
        ;;
    default)
        create_default_users
        ;;
    *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            create_default_users $1
        else
            echo -e "${RED}오류: 잘못된 인자입니다.${NC}\n"
            show_help
            exit 1
        fi
        ;;
esac
